import 'dart:convert';
import '../protocol/conversation.dart';
import 'composer_controller.dart';
import 'conversation_view_state.dart';
import 'composer_input.dart';
import 'composer_attachments.dart';
import 'recovery_journal.dart';

String composerKey(String? device, String workspace, String? session) =>
    jsonEncode(
        [device, workspace, session?.isNotEmpty == true ? session : '@draft']);

/// Application-owned editors and operations survive task route disposal.
class ComposerStore {
  ComposerStore(
      {Map<String, String>? drafts,
      Map<String, ConversationViewState>? viewStates,
      this.onChanged,
      this.persist,
      this.recovery,
      this.referenceSessions,
      this.onPromoted})
      : drafts = drafts ?? {},
        viewStates = viewStates ?? {};
  final Map<String, String> drafts;
  final Map<String, ConversationViewState> viewStates;
  final void Function()? onChanged;
  final Future<void> Function()? persist;
  final RecoveryJournal? recovery;
  bool get durable => persist != null;
  Future<void> flush() => persist?.call() ?? Future.value();
  void changed() => onChanged?.call();
  final Future<List<Map<String, dynamic>>> Function(
          String? deviceId, String workspace, bool allWorkspaces)?
      referenceSessions;
  final inputSnapshots = <String, ComposerInputSnapshot>{};
  final attachmentDrafts = <String, List<PickedAttachment>>{};
  final void Function(ComposerController controller, String sessionId)?
      onPromoted;
  final _controllers = <String, ComposerController>{};
  final _draftConfigs = <String, Map<String, dynamic>>{};
  final _recoveries = <String, Map<String, dynamic>>{};
  final _forgottenDevices = <String>{};
  String? _deviceForKey(String key) {
    try {
      final values = jsonDecode(key);
      return values is List && values.length == 3 && values.first is String
          ? values.first
          : null;
    } catch (_) {
      return null;
    }
  }

  ComposerController obtain(
      {required ConversationTransport transport,
      required String? deviceId,
      required String workspaceKey,
      String? sessionId}) {
    final key = composerKey(deviceId, workspaceKey, sessionId);
    if (_forgottenDevices.contains(deviceId)) {
      throw StateError('device was removed');
    }
    final existing = _controllers[key];
    if (existing != null && identical(existing.transport, transport)) {
      return existing;
    }
    if (existing != null) {
      _retain(existing);
      existing.dispose();
    }
    final controller = ComposerController(
        store: this,
        transport: transport,
        deviceId: deviceId,
        workspaceKey: workspaceKey,
        sessionId: sessionId,
        draftConfig: _draftConfigs[key],
        recovery: _recoveries[key]);
    _controllers[key] = controller;
    return controller;
  }

  void saveDraftConfig(
      ComposerController controller, Map<String, dynamic> config) {
    _draftConfigs[controller.key] = Map.of(config);
    changed();
  }

  void promote(ComposerController controller, String id) {
    final old = controller.key;
    final next = composerKey(controller.deviceId, controller.workspaceKey, id);
    if (identical(_controllers[old], controller)) _controllers.remove(old);
    _draftConfigs.remove(old);
    final text = drafts.remove(old);
    if (text != null) drafts[next] = text;
    final view = viewStates.remove(old);
    if (view != null) viewStates[next] = view;
    final input = inputSnapshots.remove(old);
    if (input != null) inputSnapshots[next] = input;
    final attachments = attachmentDrafts.remove(old);
    if (attachments != null) attachmentDrafts[next] = attachments;
    _controllers[next] = controller;
    final recovery = _recoveries.remove(old);
    if (recovery != null) _recoveries[next] = recovery;
    onPromoted?.call(controller, id);
    changed();
  }

  void _retain(ComposerController controller) {
    _recoveries[controller.key] = controller.recoveryState;
  }

  void retainProvisional(String key, String id, Map<String, dynamic> config) {
    if (_forgottenDevices.contains(_deviceForKey(key))) return;
    final saved = _recoveries.putIfAbsent(key, () => {});
    saved['provisionalSessionId'] = id;
    saved['provisionalConfig'] = config;
    changed();
  }

  void queuePickedFiles(String key, List<PickedAttachment> files) {
    if (_forgottenDevices.contains(_deviceForKey(key))) return;
    if (files.isEmpty) return;
    attachmentDrafts.putIfAbsent(key, () => []).addAll(files);
    final recovery = _recoveries.putIfAbsent(key, () => {});
    final states = <Map<String, dynamic>>[
      for (final item in (recovery['attachments'] as List?) ?? const [])
        if (item is Map) Map<String, dynamic>.from(item)
    ];
    states.addAll(files.map((file) => ComposerAttachment(file).toJson()));
    recovery['attachments'] = states;
    changed();
  }

  Iterable<String> get retainedAttachmentTokens => attachmentDrafts.values
      .expand((files) => files)
      .map((file) => file.recovery?['token'])
      .whereType<String>();

  void forgetDevice(String deviceId) {
    disconnect(deviceId);
    _forgottenDevices.add(deviceId);
    bool matches(String key) => _deviceForKey(key) == deviceId;
    drafts.removeWhere((key, _) => matches(key));
    inputSnapshots.removeWhere((key, _) => matches(key));
    attachmentDrafts.removeWhere((key, _) => matches(key));
    _recoveries.removeWhere((key, _) => matches(key));
    _draftConfigs.removeWhere((key, _) => matches(key));
    viewStates.removeWhere((key, _) => matches(key));
    changed();
  }

  Map<String, dynamic> exportRecovery() {
    final entries = <String, dynamic>{};
    final keys = {
      ...drafts.keys,
      ...inputSnapshots.keys,
      ...attachmentDrafts.keys,
      ..._controllers.keys,
      ..._recoveries.keys
    };
    for (final key in keys) {
      final metadata = _controllers[key]?.recoveryState ??
          _recoveries[key] ??
          const <String, dynamic>{};
      final input =
          inputSnapshots[key]?.toJson() ?? {'text': drafts[key] ?? ''};
      final files = attachmentDrafts[key] ?? const <PickedAttachment>[];
      if (input['text'] == '' &&
          files.isEmpty &&
          metadata['uncertain'] != true) {
        continue;
      }
      entries[key] = {
        ...metadata,
        'input': input,
        'attachments': metadata['attachments'] ??
            [for (final file in files) ComposerAttachment(file).toJson()]
      };
    }
    return {'entries': entries, 'draftConfigs': _draftConfigs};
  }

  Future<void> importRecovery(
      Map raw,
      Future<PickedAttachment> Function(Map<String, dynamic>)
          restoreFile) async {
    if (raw['draftConfigs'] case final Map configs) {
      for (final item in configs.entries) {
        if (item.key is String &&
            item.value is Map &&
            !_forgottenDevices.contains(_deviceForKey(item.key)) &&
            !_controllers.containsKey(item.key)) {
          _draftConfigs.putIfAbsent(
              item.key,
              () => {
                    for (final field in [
                      'provider',
                      'model',
                      'thought',
                      'mode',
                      'followupMode'
                    ])
                      if (item.value[field] is String) field: item.value[field]
                  });
        }
      }
    }
    if (raw['entries'] case final Map entries) {
      for (final entry in entries.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final key = entry.key as String;
        if (_forgottenDevices.contains(_deviceForKey(key)) ||
            drafts.containsKey(key) ||
            _controllers.containsKey(key)) {
          continue;
        }
        final value = Map<String, dynamic>.from(entry.value);
        final input = ComposerInputSnapshot.fromJson(value['input']);
        final files = <PickedAttachment>[], states = <Map<String, dynamic>>[];
        if (value['attachments'] case final List items) {
          for (final item in items.whereType<Map>()) {
            if (item['file'] is! Map || item['file']['name'] is! String) {
              continue;
            }
            files.add(
                await restoreFile(Map<String, dynamic>.from(item['file'])));
            states.add(Map<String, dynamic>.from(item));
          }
        }
        // A late load never replaces text edited while storage was being read.
        if (_forgottenDevices.contains(_deviceForKey(key)) ||
            drafts.containsKey(key) ||
            _controllers.containsKey(key)) {
          continue;
        }
        if (input != null && input.value.text.isNotEmpty) {
          inputSnapshots[key] = input;
          final editor = ComposerInput()..restore(input);
          drafts[key] = editor.markdown;
          editor.dispose();
        }
        if (files.isNotEmpty) attachmentDrafts[key] = files;
        _recoveries[key] = {...value, 'attachments': states};
      }
    }
  }

  void disconnect(String deviceId) {
    for (final entry in _controllers.entries.toList()) {
      if (entry.value.deviceId != deviceId) continue;
      _retain(entry.value);
      entry.value.dispose();
      _controllers.remove(entry.key);
    }
  }

  void dispose() {
    for (final controller in _controllers.values.toSet()) {
      _retain(controller);
      controller.dispose();
    }
    _controllers.clear();
  }
}
