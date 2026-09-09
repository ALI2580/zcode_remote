import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// A launch-only local QA policy. It never changes a remote account setting.
class RuntimeAudit {
  static bool quotaReadOnly = false;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    quotaReadOnly = await const MethodChannel('zcode_remote/platform')
            .invokeMethod<bool>('quotaReadOnlyAudit') ??
        false;
  }
}
