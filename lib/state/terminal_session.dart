import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/terminal.dart';

enum TerminalSessionStatus { idle, creating, ready, failed, exited }

/// One integrated terminal for a workspace. Open/close and writes are explicit
/// user actions; real remote verification must use a synthetic terminal service.
class TerminalSessionController extends ChangeNotifier {
  final TerminalClient client;
  final String cwd;
  final int maxBufferChars;
  final _outputEvents = StreamController<String>.broadcast();
  final _resetEvents = StreamController<void>.broadcast();

  TerminalSessionStatus status = TerminalSessionStatus.idle;
  String? terminalId;
  String? shellLabel;
  String? fontFamily;
  double? fontSize;
  Map<String, dynamic>? theme;
  String output = '';
  Object? error;
  Object? exitCode;
  int cols = 100;
  int rows = 30;

  Stream<String> get outputStream => _outputEvents.stream;

  Stream<void> get resetStream => _resetEvents.stream;

  void Function()? _outputListener;
  void Function()? _exitListener;
  void Function()? _recoveredListener;
  int _generation = 0;
  int? _resizeCols;
  int? _resizeRows;
  bool _disposed = false;
  bool _closing = false;
  bool _recreatingAfterRecovery = false;

  TerminalSessionController({
    required this.client,
    required this.cwd,
    this.maxBufferChars = 256 * 1024,
  }) {
    _recoveredListener = _onBridgeRecovered;
    client.session.recovered.addListener(_recoveredListener!);
  }

  bool get canInput =>
      !_disposed &&
      !_closing &&
      client.session.degraded.value == null &&
      status == TerminalSessionStatus.ready &&
      terminalId != null;

  Future<void> open() async {
    if (_disposed || _closing || status == TerminalSessionStatus.ready) return;
    if (status == TerminalSessionStatus.creating) return;

    final previousId = terminalId;
    final generation = ++_generation;
    status = TerminalSessionStatus.creating;
    error = null;
    exitCode = null;
    fontFamily = null;
    fontSize = null;
    theme = null;
    output = '';
    terminalId = null;
    _resetEvents.add(null);
    notifyListeners();

    try {
      if (previousId != null) {
        try {
          await client.dispose(id: previousId);
        } catch (_) {
          // A failed prior session is rebuilt; stale dispose errors must not
          // block the user from getting a usable terminal again.
        }
      }
      final result = await client.create(
        cols: cols,
        rows: rows,
        cwd: cwd,
      );
      if (_disposed || generation != _generation) {
        await client.dispose(id: result.id);
        return;
      }
      terminalId = result.id;
      shellLabel = result.shell;
      fontFamily = result.fontFamily;
      final requestedFontSize = result.fontSize;
      if (requestedFontSize != null &&
          requestedFontSize >= 6 &&
          requestedFontSize <= 72) {
        fontSize = requestedFontSize.toDouble();
      }
      theme = result.theme;
      status = TerminalSessionStatus.ready;
      _outputListener = client.onData(result.id, (data) {
        if (_disposed || generation != _generation) return;
        _appendOutput(data);
      });
      _exitListener = client.onExit(result.id, (code) {
        if (_disposed || generation != _generation) return;
        exitCode = code;
        status = TerminalSessionStatus.exited;
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      status = TerminalSessionStatus.failed;
      error = e;
      notifyListeners();
    }
  }

  Future<void> write(String data) async {
    final id = terminalId;
    if (!canInput || id == null || data.isEmpty) return;
    if (client.session.degraded.value != null) {
      throw StateError('remote connection unavailable');
    }
    try {
      await client.write(id: id, data: data);
    } catch (e) {
      if (!_disposed && !_closing && terminalId == id) {
        status = TerminalSessionStatus.failed;
        error = e;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> resize({required int newCols, required int newRows}) async {
    final id = terminalId;
    if (!canInput || id == null) return;
    if (client.session.degraded.value != null) {
      throw StateError('remote connection unavailable');
    }
    if (newCols <= 0 || newRows <= 0) return;
    if (newCols == _resizeCols && newRows == _resizeRows) return;
    _resizeCols = newCols;
    _resizeRows = newRows;
    try {
      await client.resize(id: id, cols: newCols, rows: newRows);
    } catch (e) {
      if (!_disposed && !_closing && terminalId == id) {
        status = TerminalSessionStatus.failed;
        error = e;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> close() async {
    if (_disposed || _closing) return;
    _closing = true;
    final generation = ++_generation;
    _removeListeners();
    final id = terminalId;
    try {
      if (id != null) await client.dispose(id: id);
    } finally {
      _outputListener = null;
      _exitListener = null;
      terminalId = null;
      _resizeCols = null;
      _resizeRows = null;
      status = TerminalSessionStatus.idle;
      _closing = false;
      if (!_disposed && generation == _generation) notifyListeners();
    }
  }

  /// The official client opens a fresh workspace bridge after transport
  /// recovery and remounts the terminal component. Mirror that behavior by
  /// closing the old PTY and creating a new one only after the bridge is
  /// healthy again.
  Future<void> _onBridgeRecovered() async {
    if (_disposed || _closing || _recreatingAfterRecovery) return;
    if (client.session.recovered.value == 0) return;
    if (terminalId == null) return;

    _recreatingAfterRecovery = true;
    try {
      try {
        await close();
      } catch (_) {
        // A failed dispose must not leave the UI without a fresh terminal
        // after the bridge has already been remounted.
      }
      if (_disposed || _closing) return;
      await open();
    } finally {
      _recreatingAfterRecovery = false;
    }
  }

  void _appendOutput(String data) {
    if (data.isEmpty) return;
    _outputEvents.add(data);
    output += data;
    if (output.length > maxBufferChars) {
      output = output.substring(output.length - maxBufferChars);
    }
    notifyListeners();
  }

  void _removeListeners() {
    _outputListener?.call();
    _exitListener?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_recoveredListener != null) {
      client.session.recovered.removeListener(_recoveredListener!);
    }
    _removeListeners();
    unawaited(_outputEvents.close());
    unawaited(_resetEvents.close());
    super.dispose();
  }
}
