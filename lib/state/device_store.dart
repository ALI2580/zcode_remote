import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../protocol/connection_params.dart';
import '../protocol/id.dart';
import 'credential_cipher.dart';

// Uri.origin accepts HTTP(S), while WSS identifies the same secure host.
String _connectionOrigin(ZemoteConnectionParams params) =>
    params.source.replace(scheme: 'https').origin;

class Device {
  const Device(
      {required this.id,
      required this.label,
      required this.url,
      required this.addedAt,
      required this.lastUsedAt,
      this.machineId,
      this.origin});
  final String id;
  final String label;

  /// Plaintext in memory; encryption happens at the persistence boundary.
  final String url;
  final int addedAt;
  final int lastUsedAt;
  final String? machineId;
  final String? origin;
  ZemoteConnectionParams? get params => ZemoteConnectionParams.parse(url);
  String? get endpointOrigin {
    final connection = params;
    return origin ??
        (connection == null ? null : _connectionOrigin(connection));
  }

  Device copyWith(
          {String? id,
          String? label,
          String? url,
          int? lastUsedAt,
          String? machineId,
          String? origin}) =>
      Device(
          id: id ?? this.id,
          label: label ?? this.label,
          url: url ?? this.url,
          addedAt: addedAt,
          lastUsedAt: lastUsedAt ?? this.lastUsedAt,
          machineId: machineId ?? this.machineId,
          origin: origin ?? this.origin);
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'addedAt': addedAt,
        'lastUsedAt': lastUsedAt,
        'machineId': machineId,
        'origin': origin,
      };
  factory Device.fromJson(Map<String, dynamic> json) => Device(
      id: json['id'] as String,
      label: json['label'] as String? ?? '桌面设备',
      url: json['url'] as String,
      addedAt: json['addedAt'] as int? ?? 0,
      lastUsedAt: json['lastUsedAt'] as int? ?? json['addedAt'] as int? ?? 0,
      machineId: json['machineId'] as String?,
      origin: json['origin'] as String?);
}

class DeviceStore extends ChangeNotifier {
  DeviceStore(
      {Future<String?> Function(String)? encrypt,
      Future<String?> Function(String)? decrypt,
      bool? requireEncryption})
      : _encrypt = encrypt ?? CredentialCipher.encrypt,
        _decrypt = decrypt ?? CredentialCipher.decrypt,
        _requireEncryption = requireEncryption ?? CredentialCipher.isSupported;
  static const prefsKey = 'zcode_remote_devices_v1';
  final Future<String?> Function(String) _encrypt;
  final Future<String?> Function(String) _decrypt;
  final bool _requireEncryption;
  final List<Device> _devices = [];
  Future<void>? _loading;
  Future<void> _mutations = Future.value();
  bool _loaded = false;
  int _clock = 0;
  List<Device> get devices => List.unmodifiable(_devices);
  bool get loaded => _loaded;
  Device? get lastUsed => _devices.isEmpty
      ? null
      : (_devices.toList()
            ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt)))
          .first;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    final items = <Device>[];
    bool migrated = false;
    if (raw != null) {
      dynamic list;
      try {
        list = jsonDecode(raw);
      } catch (_) {
        list = null;
      }
      if (list is List) {
        for (final entry in list.whereType<Map>()) {
          try {
            var device = Device.fromJson(entry.cast<String, dynamic>());
            if (CredentialCipher.isEncrypted(device.url)) {
              final plain = await _decrypt(device.url);
              if (plain != null) device = device.copyWith(url: plain);
            } else if (_requireEncryption) {
              migrated = true;
            }
            final params = device.params;
            if (params != null) {
              if (device.id == params.deviceSid) {
                device = device.copyWith(id: generateUuid());
                migrated = true;
              }
              device = device.copyWith(
                  machineId: params.deviceMid,
                  origin: _connectionOrigin(params));
            }
            items.add(device);
            if (device.lastUsedAt > _clock) _clock = device.lastUsedAt;
          } catch (_) {
            // One malformed row must not discard other devices.
          }
        }
      }
    }
    if (migrated) await _persist(items);
    _devices
      ..clear()
      ..addAll(items);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist(List<Device> devices) async {
    final output = <Map<String, dynamic>>[];
    for (final device in devices) {
      final map = device.toJson();
      if (!CredentialCipher.isEncrypted(device.url)) {
        final encrypted = await _encrypt(device.url);
        if (_requireEncryption && encrypted == null) {
          throw StateError('无法加密设备凭据，请重试');
        }
        map['url'] = encrypted ?? device.url;
      }
      output.add(map);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(prefsKey, jsonEncode(output))) {
      throw StateError('无法保存设备');
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _mutations.then((_) async {
      await load();
      return action();
    });
    _mutations = result.then<void>((_) {}).catchError((_) {});
    return result;
  }

  Future<void> _commit(List<Device> next) async {
    await _persist(next);
    _devices
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  Future<Device> addUrl(String url, {String? label}) => _mutate(() async {
        final params = ZemoteConnectionParams.parse(url);
        if (params == null || params.source.host.isEmpty) {
          throw const FormatException('无效的远程控制链接');
        }
        final existing = _devices
            .where((device) =>
                device.endpointOrigin == _connectionOrigin(params) &&
                ((params.deviceMid != null &&
                        (device.machineId ?? device.params?.deviceMid) ==
                            params.deviceMid) ||
                    device.params?.deviceSid == params.deviceSid))
            .firstOrNull;
        final now = _nowMs();
        final device = Device(
            id: existing?.id ?? generateUuid(),
            label: label?.trim().isNotEmpty == true
                ? label!.trim()
                : existing?.label ?? params.deviceName ?? '桌面设备',
            url: url.trim(),
            addedAt: existing?.addedAt ?? now,
            lastUsedAt: now,
            machineId: params.deviceMid,
            origin: _connectionOrigin(params));
        final next = _devices.toList();
        if (existing == null) {
          next.add(device);
        } else {
          next[next.indexOf(existing)] = device;
        }
        await _commit(next);
        return device;
      });
  Future<void> remove(String id) => _mutate(
      () => _commit(_devices.where((device) => device.id != id).toList()));
  Future<Device> updateLink(String id, String url, {String? label}) =>
      _mutate(() async {
        final original =
            _devices.where((device) => device.id == id).firstOrNull;
        final params = ZemoteConnectionParams.parse(url);
        if (original == null || params == null || params.source.host.isEmpty) {
          throw const FormatException('设备或链接无效');
        }
        if (original.machineId != null &&
            params.deviceMid != null &&
            original.machineId != params.deviceMid) {
          throw const FormatException('链接属于另一台设备');
        }
        if (original.endpointOrigin != null &&
            original.endpointOrigin != _connectionOrigin(params)) {
          throw const FormatException('连接来源不一致');
        }
        final updated = original.copyWith(
            url: url.trim(),
            label: label?.trim().isNotEmpty == true
                ? label!.trim()
                : original.label,
            machineId: params.deviceMid,
            origin: _connectionOrigin(params),
            lastUsedAt: _nowMs());
        await _commit([
          for (final device in _devices) device.id == id ? updated : device
        ]);
        return updated;
      });
  Future<void> rename(String id, String label) => _mutate(() async {
        if (label.trim().isEmpty) return;
        await _commit([
          for (final device in _devices)
            device.id == id ? device.copyWith(label: label.trim()) : device
        ]);
      });
  Future<void> touch(String id) => _mutate(() => _commit([
        for (final device in _devices)
          device.id == id ? device.copyWith(lastUsedAt: _nowMs()) : device,
      ]));
  int _nowMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clock = now > _clock ? now : _clock + 1;
    return _clock;
  }
}
