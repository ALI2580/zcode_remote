import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/connection_params.dart';
import 'credential_cipher.dart';

/// One connected desktop machine.
class Device {
  final String id;
  String label;
  final String url;
  final int addedAt;
  int lastUsedAt;

  Device({
    required this.id,
    required this.label,
    required this.url,
    required this.addedAt,
    required this.lastUsedAt,
  });

  /// Parses the remote-control URL. Returns null when the URL is invalid.
  ZemoteConnectionParams? get params => ZemoteConnectionParams.parse(url);

  Device copyWith({String? label, int? lastUsedAt}) => Device(
        id: id,
        label: label ?? this.label,
        url: url,
        addedAt: addedAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'addedAt': addedAt,
        'lastUsedAt': lastUsedAt,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        url: json['url'] as String,
        addedAt: json['addedAt'] as int? ?? 0,
        lastUsedAt: json['lastUsedAt'] as int? ?? json['addedAt'] as int? ?? 0,
      );
}

/// Persists the device list. The connection URL (which embeds `sid`/`hash`
/// credentials) is encrypted at rest on Android via [CredentialCipher]; other
/// platforms fall back to plaintext (same constraint as the desktop web
/// client's own storage).
class DeviceStore extends ChangeNotifier {
  static const _prefsKey = 'zcode_remote_devices_v1';

  final List<Device> _devices = [];
  bool _loaded = false;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get loaded => _loaded;

  Device? get lastUsed {
    if (_devices.isEmpty) return null;
    Device? best;
    for (final d in _devices) {
      if (best == null || d.lastUsedAt > best.lastUsedAt) best = d;
    }
    return best;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _devices
          ..clear()
          ..addAll(list
              .whereType<Map>()
              .map((e) => Device.fromJson(e.cast<String, dynamic>())));
      } catch (_) {
        // Corrupted store — start fresh.
        _devices.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_devices.map((d) => d.toJson()).toList()));
  }

  /// Adds a device from a remote-control URL. Returns the new device, or
  /// throws [FormatException] when the URL can't be parsed.
  Future<Device> addUrl(String url, {String? label}) async {
    final params = ZemoteConnectionParams.parse(url);
    if (params == null) {
      throw FormatException('无效的远程控制链接');
    }
    final id = params.deviceSid.isEmpty
        ? '${DateTime.now().microsecondsSinceEpoch}'
        : params.deviceSid;
    // Re-add: reuse the existing id so a re-scanned device keeps its label
    // and its already-encrypted stored URL.
    final existing = _devices.where((d) => d.id == id).firstOrNull;
    final now = _nowMs();
    if (existing != null) {
      final updated = existing.copyWith(label: label ?? existing.label, lastUsedAt: now);
      _devices[_devices.indexOf(existing)] = updated;
      await _save();
      notifyListeners();
      return updated;
    }
    final encryptedUrl = await CredentialCipher.encrypt(url) ?? url;
    final device = Device(
      id: id,
      label: label ??
          (params.deviceSid.isEmpty ? '未命名设备' : params.deviceSid),
      url: encryptedUrl,
      addedAt: now,
      lastUsedAt: now,
    );
    _devices.add(device);
    await _save();
    notifyListeners();
    return device;
  }

  Future<void> remove(String id) async {
    _devices.removeWhere((d) => d.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> rename(String id, String label) async {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(label: label);
    await _save();
    notifyListeners();
  }

  Future<void> touch(String id) async {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(lastUsedAt: _nowMs());
    await _save();
    notifyListeners();
  }

  int _clock = 0;

  /// Monotonic millisecond clock: never returns a value equal to or lower
  /// than the previous call, so rapid touches always order correctly even
  /// when wall-clock time hasn't advanced.
  int _nowMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clock = now > _clock ? now : _clock + 1;
    return _clock;
  }
}
