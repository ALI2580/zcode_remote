import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Launches the QR scanner and resolves with the raw decoded string, or null
/// when the user closes the page without scanning.
///
/// This indirection exists so widget tests (and non-touch hosts) can inject a
/// fake scanner instead of a camera.
typedef QrScanLauncher = Future<String?> Function(BuildContext context);

Future<String?> _launchDefault(BuildContext context) => Navigator.of(context)
    .push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));

QrScanLauncher qrScanLauncher = _launchDefault;

bool get qrScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Camera page that decodes a QR code containing a remote-control link.
///
/// Keep every other file free of `mobile_scanner` imports: this plugin has no
/// Windows/desktop implementation, so the dependency must stay confined to
/// this Android/iOS-only page.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _completed = false;
  MobileScannerController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completed || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      _completed = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final en = locale != 'zh';
    String title() => en ? 'Scan to connect' : '扫码连接';
    return Scaffold(
        appBar: AppBar(title: Text(title())),
        backgroundColor: Colors.black,
        body: qrScanSupported
            ? Stack(children: [
                MobileScanner(
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _Status(
                        message: en
                            ? 'Camera unavailable. Check camera permission.'
                            : '相机不可用，请检查相机权限。',
                        en: en)),
                SafeArea(
                    child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(
                                en
                                    ? 'Point at the QR code shown by the desktop app'
                                    : '对准桌面端展示的二维码',
                                style: const TextStyle(color: Colors.white)))))
              ])
            : _Status(
                message: en
                    ? 'QR scanning is only available on phones.'
                    : '扫码仅在手机上可用。',
                en: en));
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message, required this.en});
  final String message;
  final bool en;

  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70))));
}
