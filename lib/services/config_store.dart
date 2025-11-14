import 'package:shared_preferences/shared_preferences.dart';

class ConfigStore {
  static const _keyPerusahaan = 'perusahaan';
  static const _keyTujuan = 'tujuan';
  static const _keyIsi = 'isi';

  /// Simpan nilai
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

  /// Ambil nilai
  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'perusahaan': prefs.getString(_keyPerusahaan) ?? '',
      'tujuan': prefs.getString(_keyTujuan) ?? '',
      'isi': prefs.getString(_keyIsi) ?? '',
    };
  }
}
