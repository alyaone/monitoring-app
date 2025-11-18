// lib/serial_config_page_android.dart
import 'package:flutter/material.dart';

// Menghapus semua import usb_serial, transaction, dan dart:async/convert/typed_data
// karena tidak ada koneksi serial yang dibuat di sini.

class SerialConfigPageAndroid extends StatefulWidget {
  const SerialConfigPageAndroid({super.key});
  @override
  State<SerialConfigPageAndroid> createState() => _SerialConfigPageState();
}

class _SerialConfigPageState extends State<SerialConfigPageAndroid> {
  // Semua variabel dan metode koneksi/form/log dihapus 
  // atau tidak digunakan, termasuk _ts() dan _addLog().

  @override
  void initState() {
    super.initState();
    // Tidak ada inisialisasi yang diperlukan
  }

  @override
  void dispose() {
    // Tidak ada dispose controllers/subscriptions yang diperlukan
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tampilkan hanya pesan pembatasan
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengirim Konfigurasi'),
        // Hapus actions (tombol refresh)
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, 
            children: [
              Icon(
                Icons.desktop_windows_outlined, 
                size: 64, 
                color: Colors.redAccent,
              ),
              SizedBox(height: 20),
              Text(
                "Menu ini hanya dapat diakses melalui PC",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              SizedBox(height: 12),
              Text(
                "Fitur koneksi serial ke ESP32 saat ini hanya didukung pada platform Desktop (Windows/Linux) karena keterbatasan izin dan driver COM port.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Hapus juga widget pendukung (_Section, _Labeled, _Field) karena tidak digunakan.