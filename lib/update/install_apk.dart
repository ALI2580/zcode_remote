import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('zcode_remote/platform');

/// Triggers the Android package installer for a downloaded APK file.
/// Returns false on non-Android platforms or when the file is missing.
Future<bool> installApk(String filePath) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  final file = File(filePath);
  if (!await file.exists()) return false;
  try {
    return await _channel.invokeMethod<bool>(
          'installApk',
          {'path': filePath},
        ) ??
        false;
  } on PlatformException {
    return false;
  }
}
