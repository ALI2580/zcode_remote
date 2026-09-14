import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

/// Download states for the update APK.
enum DownloadState { idle, downloading, verifying, done, failed, cancelled }

/// Progress data for the download.
class DownloadProgress {
  const DownloadProgress({
    required this.state,
    this.receivedBytes = 0,
    this.totalBytes,
    this.filePath,
    this.error,
  });
  final DownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final String? filePath;
  final String? error;

  double? get fraction => totalBytes != null && totalBytes! > 0
      ? receivedBytes / totalBytes!
      : null;
}

/// Downloads an update APK with progress reporting, cancel, retry and
/// MD5 verification.
class UpdateDownloader extends ChangeNotifier {
  UpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _cancelCompleter;
  DownloadProgress _progress =
      const DownloadProgress(state: DownloadState.idle);

  DownloadProgress get progress => _progress;
  bool get isBusy =>
      _progress.state == DownloadState.downloading ||
      _progress.state == DownloadState.verifying;

  void _update(DownloadProgress progress) {
    _progress = progress;
    notifyListeners();
  }

  /// Downloads [url] to a temp file, verifies MD5 against [md5Content]
  /// if provided. Returns the local file path on success, null on failure.
  Future<String?> download({
    required String url,
    String? md5Content,
    int maxRetries = 2,
  }) async {
    if (isBusy) return null;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final result = await _attemptDownload(url, md5Content);
      if (result != null) return result;
      if (_progress.state == DownloadState.cancelled) break;
      if (attempt < maxRetries) {
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return null;
  }

  Future<String?> _attemptDownload(String url, String? md5Content) async {
    File? file;
    try {
      _update(const DownloadProgress(state: DownloadState.downloading));
      final dir = Directory.systemTemp;
      final fileName = url.split('/').last.split('?').first;
      file = File('${dir.path}/$fileName');
      if (await file.exists()) await file.delete();

      final request = http.Request('GET', Uri.parse(url));
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final chunks = <List<int>>[];

      final completer = Completer<String?>();
      _cancelCompleter = Completer<void>();
      // Complete with null when cancel is requested.
      unawaited(_cancelCompleter!.future.then((_) {
        if (!completer.isCompleted) completer.complete(null);
      }));
      _subscription = response.stream.listen(
        (chunk) {
          chunks.add(chunk);
          received += chunk.length;
          _update(DownloadProgress(
              state: DownloadState.downloading,
              receivedBytes: received,
              totalBytes: total));
        },
        onDone: () async {
          final target = file!;
          await target.writeAsBytes(chunks.expand((c) => c).toList(),
              flush: true);
          _update(DownloadProgress(
              state: DownloadState.verifying,
              receivedBytes: received,
              totalBytes: total));
          if (md5Content != null) {
            final expected = parseMd5Hex(md5Content);
            final bytes = await target.readAsBytes();
            final actual = md5.convert(bytes).toString();
            if (expected != null && actual != expected) {
              await target.delete();
              _update(const DownloadProgress(
                  state: DownloadState.failed, error: 'MD5 mismatch'));
              completer.complete(null);
              return;
            }
          }
          _update(DownloadProgress(
              state: DownloadState.done,
              receivedBytes: received,
              totalBytes: total,
              filePath: target.path));
          completer.complete(target.path);
        },
        onError: (Object e) {
          _update(DownloadProgress(state: DownloadState.failed, error: '$e'));
          completer.complete(null);
        },
        cancelOnError: true,
      );
      return await completer.future
          .timeout(const Duration(minutes: 15), onTimeout: () => null);
    } catch (e) {
      if (_progress.state != DownloadState.cancelled) {
        _update(DownloadProgress(state: DownloadState.failed, error: '$e'));
      }
      if (file != null && await file.exists()) {
        await file.delete();
      }
      return null;
    }
  }

  /// Cancels the active download.
  Future<void> cancel() async {
    if (!isBusy) return;
    await _subscription?.cancel();
    _subscription = null;
    _update(const DownloadProgress(state: DownloadState.cancelled));
    _cancelCompleter?.complete();
  }

  /// Resets state to idle.
  void reset() {
    _update(const DownloadProgress(state: DownloadState.idle));
  }

  static String? parseMd5Hex(String content) {
    return RegExp(r'\b[0-9a-fA-F]{32}\b')
        .firstMatch(content)
        ?.group(0)
        ?.toLowerCase();
  }

  /// Verifies the downloaded APK is ready for install: file exists,
  /// non-zero size, .apk extension. Returns true when safe to hand off.
  Future<bool> preInstallCheck(String filePath,
      {int minimumBytes = 1024}) async {
    if (!filePath.endsWith('.apk')) return false;
    final file = File(filePath);
    if (!await file.exists()) return false;
    final stat = await file.stat();
    return stat.size >= minimumBytes;
  }

  /// Verifies MD5 of a downloaded file matches the expected hash.
  Future<bool> verifyMd5(String filePath, String expectedMd5) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString() == expectedMd5.toLowerCase();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client.close();
    super.dispose();
  }
}
