import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'serial_config_page_windows.dart';
import 'serial_config_page_android.dart';

class SerialConfigPage extends StatelessWidget {
  const SerialConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Windows Desktop
    if (!kIsWeb && Platform.isWindows) {
      return const SerialConfigPageWindows();
    }

    // Android
    if (!kIsWeb && Platform.isAndroid) {
      return const SerialConfigPageAndroid();
    }

    // Fallback untuk web/macos/linux: tampilkan versi Android
    return const SerialConfigPageAndroid();
  }
}
