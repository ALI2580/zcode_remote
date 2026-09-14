import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_download_state.dart';
import 'voice_errors.dart';
import 'voice_model_events.dart';
import 'voice_models.dart';

/// Manages downloaded offline ASR models without external native plugins.
/// Model storage is provided by the existing Android host channel.
class VoiceModelStore {
  VoiceModelStore({Directory? root, http.Client? client})
      : _rootOverride = root,
        _clientFactory = client == null ? null : (() => client);

  /// App-level store shared by the settings page, the composer voice button
  /// and the transcriber, so an in-flight download survives page changes.
  static final VoiceModelStore instance = VoiceModelStore();

  static const _enabledKey = 'voice_enabled_model';
  static const _platform = MethodChannel('zcode_remote/platform');
  static const _manifestName = '.voice-manifest.json';

  final Directory? _rootOverride;
  final http.Client Function()? _clientFactory;
  final Set<String> _cancelled = {};
  final Map<String, Future<void>> _active = {};
  final Map<String, double> _progress = {};
  final Map<String, VoiceDownloadState> _downloadStates = {};
  final Map<String, _VerificationStamp> _verified = {};

  Map<String, double> get progress => Map.unmodifiable(_progress);

  Map<String, VoiceDownloadState> get downloadStates =>
      Map.unmodifiable(_downloadStates);

  Future<Directory> _root() async {
    if (_rootOverride != null) {
      await _rootOverride.create(recursive: true);
      return _rootOverride;
    }
    final path = await _platform.invokeMethod<String>('voiceModelsRoot');
    if (path == null || path.isEmpty) {
      throw StateError('voice model storage unavailable');
    }
    return Directory('$path/voice-models')..create(recursive: true);
  }

  Future<Directory> directory(VoiceModelInfo model) async =>
      Directory('${(await _root()).path}/${model.id}');

  Future<bool> isDownloaded(VoiceModelInfo model) async {
    final dir = await directory(model);
    final manifest = File('${dir.path}/$_manifestName');
    if (!await manifest.exists()) return false;
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final files = data['files'];
    if (files is! Map<String, dynamic>) return false;
    for (final file in model.files) {
      final expected = files[file] as Map<String, dynamic>?;
      if (expected == null) return false;
      final target = File('${dir.path}/$file');
      if (!await target.exists()) return false;
      if (await target.length() != expected['length']) return false;
    }
    return true;
  }

  Future<void> _verifyFiles(VoiceModelInfo model) async {
    final dir = await directory(model);
    final manifest = File('${dir.path}/$_manifestName');
    if (!await manifest.exists()) {
      throw StateError('模型缺少完整性记录');
    }
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final files = data['files'];
    if (files is! Map<String, dynamic>) {
      throw StateError('模型完整性记录无效');
    }
    final stamp = <String, int>{};
    final manifestStat = await manifest.stat();
    stamp['__manifest__'] =
        manifestStat.size ^ manifestStat.modified.microsecondsSinceEpoch;
    for (final file in model.files) {
      final target = File('${dir.path}/$file');
      if (await target.exists()) {
        final stat = await target.stat();
        stamp[file] = stat.size ^ stat.modified.microsecondsSinceEpoch;
      }
    }
    final cached = _verified[model.id];
    if (cached != null && cached.matches(stamp)) return;
    for (final file in model.files) {
      final expected = files[file] as Map<String, dynamic>?;
      final target = File('${dir.path}/$file');
      if (expected == null || !await target.exists()) {
        throw StateError('模型文件不完整');
      }
      final digest = await _sha256File(target);
      if (digest != expected['sha256'] ||
          await target.length() != expected['length']) {
        throw StateError('模型文件校验失败');
      }
    }
    _verified[model.id] = _VerificationStamp(stamp);
  }

  Future<void> _writeManifest(
      VoiceModelInfo model, File archive, Directory dir) async {
    final files = <String, Map<String, Object?>>{};
    for (final file in model.files) {
      final target = File('${dir.path}/$file');
      if (!await target.exists()) throw StateError('模型文件不完整');
      final length = await target.length();
      files[file] = {
        'length': length,
        'sha256': await _sha256File(target),
      };
    }
    final archiveLength = await archive.length();
    await File('${dir.path}/$_manifestName').writeAsString(jsonEncode({
      'version': 1,
      'archive': {
        'length': archiveLength,
        'sha256': await _sha256File(archive),
      },
      'files': files,
    }));
  }

  Future<String?> enabledModelId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_enabledKey);
    if (id == null || !voiceModels.any((model) => model.id == id)) return null;
    final model = voiceModelById(id);
    try {
      if (!await isDownloaded(model)) {
        final modelDirectory = await directory(model);
        if (await modelDirectory.exists()) {
          throw const VoiceModelStoreException(
            VoiceFailureKind.modelCorrupt,
            '已启用的语音模型文件不完整，请在模型管理中重新下载',
          );
        }
        return null;
      }
      await _verifyFiles(model);
      return id;
    } catch (error) {
      final kind = error is FileSystemException
          ? VoiceFailureKind.storageUnavailable
          : VoiceFailureKind.modelCorrupt;
      throw VoiceModelStoreException(
        kind,
        kind == VoiceFailureKind.storageUnavailable
            ? '无法读取语音模型存储，请检查应用存储权限后重试'
            : '已启用的语音模型校验失败，请在模型管理中重新下载',
      );
    }
  }

  Future<void> setEnabled(VoiceModelInfo model) async {
    if (!await isDownloaded(model)) throw StateError('模型尚未下载');
    await _verifyFiles(model);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_enabledKey, model.id);
    VoiceModelEvents.notifyChanged();
  }

  Future<void> disable(VoiceModelInfo model) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_enabledKey) == model.id) {
      await prefs.remove(_enabledKey);
      VoiceModelEvents.notifyChanged();
    }
  }

  Future<void> download(VoiceModelInfo model) {
    return _active.putIfAbsent(model.id, () => _download(model));
  }

  void cancelDownload(VoiceModelInfo model) {
    if (_active.containsKey(model.id)) _cancelled.add(model.id);
  }

  Future<void> _download(VoiceModelInfo model) async {
    if (await isDownloaded(model)) return;
    final root = await _root();
    final temp = File('${root.path}/${model.id}.download');
    final dir = Directory('${root.path}/${model.id}');
    _progress[model.id] = 0;
    _downloadStates[model.id] = const VoiceDownloadState(
        VoiceDownloadPhase.downloading, received: 0, total: null);
    _cancelled.remove(model.id);
    VoiceModelEvents.notifyChanged();
    final client = _clientFactory?.call() ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(model.archiveUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw StateError('模型下载失败: HTTP ${response.statusCode}');
      }
      final sink = temp.openWrite();
      var received = 0;
      // An unknown Content-Length must show received bytes with an
      // indeterminate bar, never a fabricated or stuck 0%.
      final total = response.contentLength != null && response.contentLength! > 0
          ? response.contentLength
          : null;
      try {
        await for (final chunk in response.stream) {
          if (_cancelled.contains(model.id)) {
            throw const _Cancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          _downloadStates[model.id] = VoiceDownloadState(
              VoiceDownloadPhase.downloading,
              received: received,
              total: total);
          if (total != null) {
            _progress[model.id] = (received / total).clamp(0.0, 1.0);
          }
          VoiceModelEvents.notifyChanged();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (_cancelled.contains(model.id)) throw const _Cancelled();
      if (total != null) _progress[model.id] = 1;
      // Extract and verify outside the UI isolate: bzip2 decoding of a
      // multi-hundred-megabyte archive blocks any synchronous caller.
      _downloadStates[model.id] =
          VoiceDownloadState(VoiceDownloadPhase.extracting,
              received: received, total: total);
      VoiceModelEvents.notifyChanged();
      await _extractArchive(
          temp.path, dir.path, model.directory, model.files);
      _downloadStates[model.id] = VoiceDownloadState(
          VoiceDownloadPhase.verifying,
          received: received,
          total: total);
      VoiceModelEvents.notifyChanged();
      await _writeManifest(model, temp, dir);
      await _verifyFiles(model);
      _progress[model.id] = 1;
      VoiceModelEvents.notifyChanged();
    } catch (error) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _progress.remove(model.id);
      _downloadStates.remove(model.id);
      VoiceModelEvents.notifyChanged();
      if (error == const _Cancelled()) {
        throw StateError('模型下载已取消');
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
      _active.remove(model.id);
      _cancelled.remove(model.id);
      // The terminal state is cleared on the next refresh; keep the last
      // state visible until then so the UI can show "downloaded".
      scheduleMicrotask(() {
        if (_active.containsKey(model.id)) return;
        _downloadStates.remove(model.id);
        VoiceModelEvents.notifyChanged();
      });
    }
  }

  /// Pure-IO archive extraction; runs in a background isolate (U25).
  static Future<void> _extractArchive(String archivePath, String targetDir,
      String modelDirectory, List<String> wantedFiles) {
    return Isolate.run(() {
      final tarBytes =
          BZip2Decoder().decodeBytes(File(archivePath).readAsBytesSync());
      final archive = TarDecoder().decodeBytes(tarBytes);
      for (final file in archive.where((entry) => entry.isFile)) {
        final relative = file.name.replaceFirst('$modelDirectory/', '');
        if (!wantedFiles.contains(relative)) continue;
        final output = File('$targetDir/$relative');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(file.content as List<int>);
      }
    });
  }

  Future<void> delete(VoiceModelInfo model) async {
    await disable(model);
    final dir = await directory(model);
    if (await dir.exists()) await dir.delete(recursive: true);
    _progress.remove(model.id);
    _verified.remove(model.id);
    VoiceModelEvents.notifyChanged();
  }
}

class _VerificationStamp {
  _VerificationStamp(Map<String, int> files) : files = Map.unmodifiable(files);
  final Map<String, int> files;
  bool matches(Map<String, int> next) =>
      files.length == next.length &&
      files.entries.every((entry) => next[entry.key] == entry.value);
}

Future<String> _sha256File(File file) async {
  return Isolate.run(() => _sha256FilePath(file.path));
}

Future<String> _sha256FilePath(String path) async {
  final digest = _DigestCollector();
  final converter = sha256.startChunkedConversion(digest);
  await for (final chunk in File(path).openRead()) {
    converter.add(chunk);
  }
  converter.close();
  return digest.value.toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest event) {
    value = event;
  }

  @override
  void close() {}
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Reads the configured model without validating its files.
Future<String?> configuredVoiceModelId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(VoiceModelStore._enabledKey);
}

/// Validates one model only. This avoids using enabledModelId(), whose global
/// configured-model lookup is intentionally stricter than a catalog scan.
Future<void> verifyVoiceModelFiles(
    VoiceModelStore store, VoiceModelInfo model) async {
  if (store.runtimeType != VoiceModelStore) {
    if (!await store.isDownloaded(model)) {
      throw const VoiceModelStoreException(
          VoiceFailureKind.modelCorrupt, '模型文件不完整');
    }
    return;
  }
  await store._verifyFiles(model);
}
