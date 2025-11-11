import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Halaman konfigurasi via COM port (Windows)
class SerialConfigPage extends StatefulWidget {
  const SerialConfigPage({super.key});

  @override
  State<SerialConfigPage> createState() => _SerialConfigPageState();
}

class _SerialConfigPageState extends State<SerialConfigPage> {
  // ==== Variabel utama ====
  List<String> _ports = [];
  String? _selectedPort;
  SerialPort? _port;
  SerialPortReader? _reader;

  bool _connected = false;
  int _baud = 115200;
  final _baudRates = const [9600, 38400, 57600, 115200];

  // ==== Form konfigurasi ====
  final _perusahaan = TextEditingController();
  final _tujuan = TextEditingController();
  final _isi = TextEditingController();

  // ==== Log ====
  final List<String> _logs = [];
  final ScrollController _logCtrl = ScrollController();

  String _ts() {
  final n = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  String three(int x) => x.toString().padLeft(3, '0');
  return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${three(n.millisecond)}';
}

void _addLog(String s) {
  setState(() => _logs.add('[${_ts()}] $s'));   // ← timestamp ditambahkan di sini
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_logCtrl.hasClients) {
      _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
    }
  });
}


  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  @override
  void dispose() {
    _disconnect();
    _perusahaan.dispose();
    _tujuan.dispose();
    _isi.dispose();
    _logCtrl.dispose();
    super.dispose();
  }


  // === Mendapatkan daftar COM port ===
  void _refreshPorts() {
    final availablePorts = SerialPort.availablePorts;
    setState(() {
      _ports = availablePorts;
      if (_ports.isNotEmpty) {
        _selectedPort ??= _ports.first;
      } else {
        _selectedPort = null;
      }
    });
  }

  // === Koneksi ke COM port ===
  Future<void> _connect() async {
    if (_selectedPort == null) {
      _addLog('[ERR] Tidak ada port terpilih.');
      return;
    }

    await _disconnect(); // pastikan tidak double connect
    try {
      _port = SerialPort(_selectedPort!);
      if (!_port!.openReadWrite()) {
        _addLog('[ERR] Gagal membuka port $_selectedPort');
        _port = null;
        return;
      }

      // Set parameter port
      _port!.config.baudRate = _baud;
      _port!.config.bits = 8;
      _port!.config.stopBits = 1;
      _port!.config.parity = 0;

      // Reader stream untuk RX data
      _reader = SerialPortReader(_port!);
      _reader!.stream.listen(
        (Uint8List data) {
          final text = utf8.decode(data, allowMalformed: true);
          for (final line in const LineSplitter().convert(text)) {
            _addLog('RX ← $line');
          }
        },
        onError: (e) => _addLog('[ERR] $e'),
        onDone: () => setState(() => _connected = false),
      );

      setState(() => _connected = true);
      _addLog('[OK] Connected to $_selectedPort @ $_baud bps');
    } catch (e) {
      _addLog('[ERR] $e');
      _disconnect();
    }
  }

  // === Putuskan koneksi ===
  Future<void> _disconnect() async {
    _reader?.close();
    _reader = null;
    if (_port != null && _port!.isOpen) {
      try {
        _port!.close();
      } catch (_) {}
    }
    _port = null;
    setState(() => _connected = false);
  }

  // === Kirim JSON ke ESP32 ===
  Future<void> _sendJson() async {
    if (_port == null || !_port!.isOpen) {
      _addLog('[ERR] Belum terhubung.');
      return;
    }
    final payload = {
      'perusahaan': _perusahaan.text.trim(),
      'tujuan': _tujuan.text.trim(),
      'isi': _isi.text.trim(),
    };
    final line = jsonEncode(payload) + '\n';
    final data = Uint8List.fromList(utf8.encode(line));
    final written = _port!.write(data);
    _addLog('TX → ($written B) ${line.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengirim Konfigurasi → ESP32 (JSON over Serial)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh port',
            onPressed: connected ? null : _refreshPorts,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ======== Bagian 1: Koneksi Serial ========
            _Section(
              title: 'Koneksi Serial',
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Labeled(
                    label: 'Port',
                    child: DropdownButton<String>(
                      value: _selectedPort,
                      hint: const Text('Pilih port'),
                      items: _ports
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: connected ? null : (v) => setState(() => _selectedPort = v),
                    ),
                  ),
                  _Labeled(
                    label: 'Baud',
                    child: DropdownButton<int>(
                      value: _baud,
                      items: _baudRates
                          .map((b) => DropdownMenuItem(value: b, child: Text('$b')))
                          .toList(),
                      onChanged: connected ? null : (v) => setState(() => _baud = v ?? _baud),
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (connected) {
                        await _disconnect();
                      } else {
                        await _connect();
                      }
                    },
                    child: Text(connected ? 'Disconnect' : 'Connect'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ======== Bagian 2: Data Konfigurasi ========
            _Section(
              title: 'Data Konfigurasi',
              child: Column(
                children: [
                  _Field(label: 'Perusahaan (≤31)', controller: _perusahaan, maxLen: 31, hint: 'PT CHATGPT Yogyakarta'),
                  const SizedBox(height: 8),
                  _Field(label: 'Tujuan (≤31)', controller: _tujuan, maxLen: 31, hint: 'Yogyakarta'),
                  const SizedBox(height: 8),
                  _Field(label: 'Isi (≤95)', controller: _isi, maxLen: 95, hint: 'Alat Elektronik'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: connected ? () async => _sendJson() : null,
                        child: Text('Kirim ke ESP32'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: () => _addLog('[INFO] Isian disimpan lokal (contoh).'),
                        child: Text('Simpan Isian'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ======== Bagian 3: Log (full sampai bawah) ========
Expanded(
  child: _Section(
    title: 'Log',
    child: Expanded( // <- penting: biar ListView mengisi _Section
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ListView.builder(
  controller: _logCtrl,
  itemCount: _logs.length,
  itemBuilder: (_, i) => Text(
    _logs[i],
    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    softWrap: true,
  ),
),

        ),
      ),
    ),
  ),
),


          ],
        ),
      ),
    );
  }
}

/* ---------- Widget kecil pendukung UI ---------- */

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 70, child: Text(label)),
        const SizedBox(width: 8),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final int? maxLen;
  final int maxLines;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLen,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLen,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        counterText: '',
      ).copyWith(labelText: label),
    );
  }
}
