// import 'package:shared_preferences/shared_preferences.dart';

// class ConfigStore {
//   static const _keyPerusahaan = 'perusahaan';
//   static const _keyTujuan = 'tujuan';
//   static const _keyIsi = 'isi';

//   /// Simpan nilai
//   static Future<void> save({
//     required String perusahaan,
//     required String tujuan,
//     required String isi,
//   }) async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString(_keyPerusahaan, perusahaan);
//     await prefs.setString(_keyTujuan, tujuan);
//     await prefs.setString(_keyIsi, isi);
//   }

//   /// Ambil nilai
//   static Future<Map<String, String>> load() async {
//     final prefs = await SharedPreferences.getInstance();
//     return {
//       'perusahaan': prefs.getString(_keyPerusahaan) ?? '',
//       'tujuan': prefs.getString(_keyTujuan) ?? '',
//       'isi': prefs.getString(_keyIsi) ?? '',
//     };
//   }
// }
import 'package:shared_preferences/shared_preferences.dart';

class ConfigStore {
  // ---- Keys lama (GUI transmitter) ----
  static const _keyPerusahaan = 'perusahaan';
  static const _keyTujuan = 'tujuan';
  static const _keyIsi = 'isi';

  // ---- Keys baru (InfluxDB Cloud + lokal) ----
  static const _keyInfluxUrl1 = 'influxUrl1';
  static const _keyInfluxToken1 = 'influxToken1';
  static const _keyInfluxOrg = 'influxOrg';
  static const _keyInfluxBucket = 'influxBucket';
  static const _keyInfluxUrl2 = 'influxUrl2';
  static const _keyInfluxToken2 = 'influxToken2';

  /// Simpan nilai dasar GUI transmitter
  static Future<void> save({
    required String perusahaan,
    required String tujuan,
    required String isi,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPerusahaan, perusahaan);
    await prefs.setString(_keyTujuan, tujuan);
    await prefs.setString(_keyIsi, isi);
  }

  /// Simpan konfigurasi Influx (Cloud + Lokal)
  static Future<void> saveInflux({
    required String influxUrl1,
    required String influxToken1,
    required String influxOrg,
    required String influxBucket,
    String influxUrl2 = '',
    String influxToken2 = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInfluxUrl1, influxUrl1);
    await prefs.setString(_keyInfluxToken1, influxToken1);
    await prefs.setString(_keyInfluxOrg, influxOrg);
    await prefs.setString(_keyInfluxBucket, influxBucket);
    await prefs.setString(_keyInfluxUrl2, influxUrl2);
    await prefs.setString(_keyInfluxToken2, influxToken2);
  }

  /// Ambil semua konfigurasi (gabungan lama + baru)
  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      // GUI transmitter
      'perusahaan': prefs.getString(_keyPerusahaan) ?? '',
      'tujuan': prefs.getString(_keyTujuan) ?? '',
      'isi': prefs.getString(_keyIsi) ?? '',

      // Influx Cloud
      'influxUrl1': prefs.getString(_keyInfluxUrl1) ?? '',
      'influxToken1': prefs.getString(_keyInfluxToken1) ?? '',
      'influxOrg': prefs.getString(_keyInfluxOrg) ?? '',
      'influxBucket': prefs.getString(_keyInfluxBucket) ?? '',

      // Influx lokal (backup)
      'influxUrl2': prefs.getString(_keyInfluxUrl2) ?? '',
      'influxToken2': prefs.getString(_keyInfluxToken2) ?? '',
    };
  }

  /// Reset semua konfigurasi (opsional)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
