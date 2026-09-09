import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_cipher.dart';

abstract interface class RecoveryStorage {
  Future<List<String>> readCandidates();
  Future<void> write(String value, String? previous);
}

class RecoveryVersionMismatch implements Exception {
  const RecoveryVersionMismatch();
}

class PreferencesRecoveryStorage implements RecoveryStorage {
  static const key = 'zcode_remote_workspace_recovery_v1';
  static const backupKey = '${key}_previous';
  @override
  Future<List<String>> readCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      if (prefs.getString(key) case final String value) value,
      if (prefs.getString(backupKey) case final String value) value,
    ];
  }

  @override
  Future<void> write(String value, String? previous) async {
    final prefs = await SharedPreferences.getInstance();
    if (previous != null && !await prefs.setString(backupKey, previous)) {
      throw StateError('recovery backup write failed');
    }
    if (!await prefs.setString(key, value)) {
      throw StateError('recovery write failed');
    }
  }
}

/// Saves only local editor/navigation state, never connection credentials or
/// message history. Writes coalesce but serialize; explicit send/lifecycle
/// boundaries can await flush before continuing.
class RecoveryJournal extends ChangeNotifier {
  RecoveryJournal(
      {required this.storage,
      required this.encrypted,
      Future<String?> Function(String)? encrypt,
      Future<String?> Function(String)? decrypt})
      : _encrypt = encrypt ?? CredentialCipher.encrypt,
        _decrypt = decrypt ?? CredentialCipher.decrypt;
  factory RecoveryJournal.production() => RecoveryJournal(
      storage: PreferencesRecoveryStorage(),
      encrypted: CredentialCipher.isSupported);
  final RecoveryStorage storage;
  final bool encrypted;
  final Future<String?> Function(String) _encrypt, _decrypt;
  Map<String, dynamic> Function()? capture;
  bool failed = false;
  bool recoveredBackup = false;
  bool _active = false, _dirty = false, _disposed = false;
  Future<void>? _writing;
  String? _lastBlob, _lastJson;

  Future<Map<String, dynamic>> load() async {
    try {
      final candidates = await storage.readCandidates();
      if (candidates.isEmpty) return {};
      for (var i = 0; i < candidates.length; i++) {
        try {
          final blob = candidates[i];
          final plain = CredentialCipher.isEncrypted(blob)
              ? await _decrypt(blob)
              : encrypted
                  ? null
                  : blob;
          if (plain == null) continue;
          final parsed = jsonDecode(plain);
          if (parsed is Map &&
              parsed['schemaVersion'] is num &&
              parsed['schemaVersion'] > 1) {
            throw const RecoveryVersionMismatch();
          }
          if (parsed is! Map || parsed['schemaVersion'] != 1) continue;
          _lastBlob = blob;
          recoveredBackup = i > 0;
          _failure(false);
          return Map<String, dynamic>.from(parsed);
        } catch (error) {
          if (error is RecoveryVersionMismatch) rethrow;
          // The previous valid snapshot remains an independent recovery source.
        }
      }
      throw StateError('local workspace recovery unavailable');
    } catch (_) {
      _failure(true);
      rethrow;
    }
  }

  void activate() {
    _active = true;
    if (_dirty) schedule();
  }

  void schedule() {
    _dirty = true;
    if (!_active || _disposed || _writing != null) return;
    final operation = Future<void>.microtask(() async {
      try {
        while (_dirty) {
          _dirty = false;
          final json = jsonEncode(capture!());
          if (json == _lastJson) continue;
          final blob = encrypted ? await _encrypt(json) : json;
          if (blob == null ||
              encrypted && !CredentialCipher.isEncrypted(blob)) {
            throw StateError('local workspace encryption unavailable');
          }
          await storage.write(blob, _lastBlob);
          _lastBlob = blob;
          _lastJson = json;
        }
        _failure(false);
      } catch (_) {
        _dirty = true;
        _failure(true);
        rethrow;
      }
    });
    _writing = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_writing, operation)) _writing = null;
      if (_dirty && !failed) schedule();
    }).catchError((_) {}));
  }

  Future<void> flush() {
    if (!_active) {
      return Future.error(StateError('workspace recovery is not ready'));
    }
    schedule();
    return _writing ?? Future.value();
  }

  void _failure(bool value) {
    if (failed == value) return;
    failed = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
