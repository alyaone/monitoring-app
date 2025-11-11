// lib/serial_config_page_android.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

class SerialConfigPage extends StatefulWidget {
  const SerialConfigPage({super.key});
  @override
  State<SerialConfigPage> createState() => _SerialConfigPageState();
}

class _SerialConfigPageState extends State<SerialConfigPage> {
  // === Perangkat & koneksi ===
  List<UsbDevice> _devices = [];
  UsbDevice? _selected;
  UsbPort? _port;

  Transaction<String>? _transaction;
  StreamSubscription<String>? _rxSub;
  StreamSubscription<UsbEvent>? _usbEvents;

  bool _connected = false;
  int _baud = 115200;
  final _baudRates = const [9600, 38400, 57600, 115200];

  // === Form ===
  final _perusahaan = TextEditingController();
  final _tujuan = TextEditingController();
  final _isi = TextEditingController();

  // === Log ===
  final List<String> _logs = [];
  final ScrollController _logCtrl = ScrollController();

  // ---------- util log + timestamp ----------
  String _ts() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    String three(int x) => x.toString().padLeft(3, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${three(n.millisecond)}';
  }

  void _addLog(String s) {
    setState(() => _logs.add('[${_ts()}] $s'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshDevices();
    _usbEvents = UsbSerial.usbEventStream?.listen((_) => _refreshDevices());
  }

  @override
  void dispose() {
    _disconnect();
    _usbEvents?.cancel();
    _perusahaan.dispose();
    _tujuan.dispose();
    _isi.dispose();
    _logCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    final list = await UsbSerial.listDevices();
    setState(() {
      _devices = list;
      if (_devices.isNotEmpty &&
          (_selected == null || !_devices.contains(_selected))) {
        _selected = _devices.first;
      } else if (_devices.isEmpty) {
        _selected = null;
      }
    });
  }

  Future<void> _connect() async {
    if (_selected == null) {
      _addLog('[ERR] Tidak ada perangkat USB terpilih.');
      return;
    }
    await _disconnect();

    // minta izin dulu
    final hasPerm = await _selected!.requestPermission();
    if (hasPerm != true) {
      _addLog('[ERR] Izin USB ditolak.');
      return;
    }

    _port = await _selected!.create();
    if (!await _port!.open()) {
      _addLog('[ERR] Gagal open port.');
      _port = null;
      return;
    }

    // set parameter
    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
      _baud,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    // baca baris (akhiran '\n')
    _transaction = Transaction.stringTerminated(
      _port!.inputStream!,
      Uint8List.fromList([10]),
    );

    _rxSub = _transaction!.stream.listen((line) {
      _addLog('RX ← $line');
    }, onError: (e) {
      _addLog('[ERR] $e');
    }, onDone: () {
      _addLog('[INFO] Port closed');
      setState(() => _connected = false);
    });

    setState(() => _connected = true);
    final name = _selected!.productName ?? 'USB';
    _addLog('[OK] Connected $name @ $_baud bps');
  }

  Future<void> _disconnect() async {
    await _rxSub?.cancel();
    _rxSub = null;
    _transaction?.dispose();
    _transaction = null;

    if (_port != null) {
      try {
        await _port!.close();
      } catch (_) {}
      _port = null;
    }
    setState(() => _connected = false);
  }

  Future<void> _sendJson() async {
    if (_port == null) {
      _addLog('[ERR] Belum terhubung.');
      return;
    }
    final payload = {
      'perusahaan': _perusahaan.text.trim(),
      'tujuan': _tujuan.text.trim(),
      'isi': _isi.text.trim(),
    };
    final line = jsonEncode(payload) + '\n';
    final n = await _port!.write(Uint8List.fromList(utf8.encode(line)));
    _addLog('TX → ($n B) ${line.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengirim Konfigurasi → ESP32 (JSON over Serial)'),
        actions: [
          IconButton(
            tooltip: 'Refresh perangkat',
            onPressed: connected ? null : _refreshDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ===== Koneksi Serial =====
            _Section(
              title: 'Koneksi Serial',
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Labeled(
                    label: 'Perangkat',
                    child: DropdownButton<UsbDevice>(
                      value: _selected,
                      hint: const Text('Pilih perangkat'),
                      items: _devices.map((d) {
                        final name =
                            '${d.productName ?? "USB"} (${d.vid}:${d.pid})';
                        return DropdownMenuItem(value: d, child: Text(name));
                      }).toList(),
                      onChanged:
                          connected ? null : (v) => setState(() => _selected = v),
                    ),
                  ),
                  _Labeled(
                    label: 'Baud',
                    child: DropdownButton<int>(
                      value: _baud,
                      items: _baudRates
                          .map((b) => DropdownMenuItem(value: b, child: Text('$b')))
                          .toList(),
                      onChanged:
                          connected ? null : (v) => setState(() => _baud = v ?? _baud),
                    ),
                  ),
                  FilledButton(
                    onPressed: () async =>
                        connected ? _disconnect() : _connect(),
                    child: Text(connected ? 'Disconnect' : 'Connect'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ===== Data Konfigurasi =====
            _Section(
              title: 'Data Konfigurasi',
              child: Column(
                children: [
                  _Field(
                    label: 'Perusahaan (≤31)',
                    controller: _perusahaan,
                    maxLen: 31,
                    hint: 'PT CHATGPT Yogyakarta',
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    label: 'Tujuan (≤31)',
                    controller: _tujuan,
                    maxLen: 31,
                    hint: 'Yogyakarta',
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    label: 'Isi (≤95)',
                    controller: _isi,
                    maxLen: 95,
                    maxLines: 4,
                    hint: 'Alat Elektronik',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: connected ? _sendJson : null,
                        child: const Text('Kirim ke ESP32'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: () => _addLog(
                            '[INFO] Isian disimpan lokal (contoh).'),
                        child: const Text('Simpan Isian'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ===== Log (penuh sampai bawah) =====
            Expanded(
              child: _Section(
                title: 'Log',
                child: Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: ListView.builder(
                        controller: _logCtrl,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
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

/* ---------- Widget pendukung (sama seperti Windows) ---------- */

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
        border:
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
        SizedBox(width: 78, child: Text(label)),
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
