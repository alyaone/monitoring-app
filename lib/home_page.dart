import 'package:flutter/material.dart';
import 'services/config_store.dart';
import 'serial_config_page_windows.dart'; // biar bisa buka halaman config

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String perusahaan = '';
  String tujuan     = '';
  String isi        = '';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final m = await ConfigStore.load();
    if (!mounted) return;
    setState(() {
      perusahaan = m['perusahaan']!;
      tujuan     = m['tujuan']!;
      isi        = m['isi']!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring Posisi Kontainer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Buka konfigurasi ESP32',
            onPressed: () async {
              // buka halaman config; setelah kembali, refresh data
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SerialConfigPage(),
                ),
              );
              _loadSaved();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoTile('Perusahaan', perusahaan),
            const SizedBox(height: 8),
            _infoTile('Tujuan', tujuan),
            const SizedBox(height: 8),
            _infoTile('Isi', isi),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadSaved,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value),
          ),
        ],
      ),
    );
  }
}
