import 'dart:async';

import 'channel_client.dart';
import 'zemote_client.dart';

/// Official integrated-terminal create response (`terminalService.create`).
class TerminalCreateResult {
  final String id;
  final String? shell;
  final String? fontFamily;
  final num? fontSize;
  final Map<String, dynamic>? theme;
  final String? fontFamilySource;
  final Map<String, dynamic>? windowsPty;
  final Map<String, dynamic> raw;

  const TerminalCreateResult({
    required this.id,
    required this.shell,
    required this.fontFamily,
    required this.fontSize,
    required this.theme,
    required this.fontFamilySource,
    required this.windowsPty,
    required this.raw,
  });
}

class TerminalFormatException implements Exception {
  final String message;
  const TerminalFormatException(this.message);

  @override
  String toString() => 'TerminalFormatException: $message';
}

/// Thin, pure-Dart wrapper for the official terminal channel.
///
/// The desktop client accesses a generic channel proxy, whose visible calls
/// are `create`, `write`, `resize` and `dispose`; terminal output and process
/// exit are `onDynamicData(id)` and `onDynamicExit(id)`.
class TerminalClient {
  final BridgeSession session;
  final Duration timeout;

  TerminalClient({
    required this.session,
    this.timeout = const Duration(seconds: 30),
  });

  ChannelClient get _channels => session.channels;

  Future<TerminalCreateResult> create({
    required int cols,
    required int rows,
    String? cwd,
  }) async {
    await session.waitHealthy(timeout: timeout);
    final raw = await _channels.call(
      Channels.terminal,
      'create',
      [
        {
          'cols': cols,
          'rows': rows,
          if (cwd != null) 'cwd': cwd,
        },
      ],
      timeout: timeout,
    );
    if (raw is! Map) {
      throw const TerminalFormatException('create response is not an object');
    }
    final map = raw.cast<String, dynamic>();
    final id = map['id'];
    if (id is! String || id.isEmpty) {
      throw const TerminalFormatException('terminal id missing or invalid');
    }
    return TerminalCreateResult(
      id: id,
      shell: _string(map['shell']),
      fontFamily: _string(map['fontFamily']),
      fontSize: map['fontSize'] is num ? map['fontSize'] as num : null,
      theme: map['theme'] is Map
          ? (map['theme'] as Map).cast<String, dynamic>()
          : null,
      fontFamilySource: _string(map['fontFamilySource']),
      windowsPty: map['windowsPty'] is Map
          ? (map['windowsPty'] as Map).cast<String, dynamic>()
          : null,
      raw: map,
    );
  }

  Future<void> write({required String id, required String data}) =>
      _voidCall('write', {'id': id, 'data': data});

  Future<void> resize({
    required String id,
    required int cols,
    required int rows,
  }) =>
      _voidCall('resize', {'id': id, 'cols': cols, 'rows': rows});

  Future<void> dispose({required String id}) =>
      _voidCall('dispose', {'id': id});

  /// Output stream. The official renderer writes the event value directly to
  /// xterm, so this listener intentionally requires a string payload.
  void Function() onData(
    String id,
    void Function(String data) listener,
  ) =>
      _listen('onDynamicData', id, listener, _validateData);

  /// Process exit. The official renderer renders the value via string
  /// interpolation and supports auto-close, so preserve its natural payload.
  void Function() onExit(
    String id,
    void Function(Object? exitCode) listener,
  ) =>
      _listen('onDynamicExit', id, listener, identity);

  void Function() _listen<T>(
    String event,
    String id,
    void Function(T payload) listener,
    T? Function(dynamic payload) convert,
  ) =>
      _channels.addEventListener(
        Channels.terminal,
        event,
        (raw) {
          final value = convert(raw);
          if (value != null) listener(value);
        },
        arg: id,
      );

  String? _validateData(dynamic payload) => payload is String ? payload : null;

  T identity<T>(T value) => value;

  String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  Future<void> _voidCall(String method, Map<String, dynamic> args) async {
    await session.waitHealthy(timeout: timeout);
    await _channels.call(
      Channels.terminal,
      method,
      [args],
      timeout: timeout,
    );
  }
}
