import 'package:flutter/material.dart';

class SerialConfigPage extends StatelessWidget {
  const SerialConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konfigurasi via Serial')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Halaman ini hanya tersedia di Android (USB-OTG).\n'
            'Jalankan di perangkat Android agar koneksi USB bisa digunakan.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
