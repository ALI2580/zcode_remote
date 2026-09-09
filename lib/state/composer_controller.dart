import 'dart:async';
import 'package:flutter/foundation.dart';
import '../protocol/conversation.dart';
import 'composer_config.dart';
import 'composer_store.dart';
import 'composer_usage.dart';
import 'composer_attachments.dart';
import 'composer_input.dart';
import 'composer_references.dart';
import 'composer_command.dart';

enum ComposerFailure {
  preparation,
  configuration,
  send,
  uncertain,
  stop,
  queue,
  queueChanged,
  command
}

enum ComposerSendResult { sent, blocked, failed, confirmationRequired }

class _ConfigIntent {
  _ConfigIntent(this.kind, this.value, {this.model, this.provider});
  final String kind;
  final String value;
  final String? model;
  final String? provider;
  final done = Completer<bool>();
}

/// One device/workspace/session. Never copies a draft into an existing session.
class ComposerController extends ChangeNotifier {
  ComposerController(
      {required this.store,
      required this.transport,
      required this.deviceId,
      required this.workspaceKey,
      String? sessionId,
      Map<String, dynamic>? draftConfig,
      Map<String, dynamic>? recovery})
      : sessionId = sessionId?.isNotEmpty == true ? sessionId : null,
        _confirmed = Map.of(draftConfig ?? {}) {
    usage = ComposerUsage(transport)..addListener(_usageChanged);
    attachments = ComposerAttachments(
        transport: transport, ensureSession: _ensureAttachmentSession)
      ..addListener(_attachmentsChanged);
    references = ComposerReferences(
        input: input,
        transport: transport,
        preparation: () => prep,
        session: () => sessionId,
        sessionCatalog: store.referenceSessions == null
            ? null
            : (all) => store.referenceSessions!(deviceId, workspaceKey, all))
      ..addListener(_usageChanged);
    input.text = store.drafts[key] ?? '';
    if (store.inputSnapshots[key] case final ComposerInputSnapshot snapshot) {
      input.restore(snapshot);
    }
    if (sessionId == null &&
        recovery?['provisionalSessionId'] is String &&
        (recovery!['provisionalSessionId'] as String).isNotEmpty) {
      _attachmentSessionId = recovery['provisionalSessionId'];
      if (recovery['provisionalConfig'] is Map) {
        _attachmentConfig =
            Map<String, dynamic>.from(recovery['provisionalConfig']);
      }
    }
    if (recovery?['uncertain'] == true) {
      failure = ComposerFailure.uncertain;
      _attachmentPromotionPending = _attachmentSessionId != null;
    } else if (recovery?['failure'] == 'send') {
      failure = ComposerFailure.send;
    }
    final files = store.attachmentDrafts[key];
    if (files != null) {
      final states = recovery?['attachments'] is List
          ? (recovery!['attachments'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (this.sessionId == null && _attachmentSessionId == null) {
        for (final state in states) {
          if (state['phase'] == 'ready') state['phase'] = 'waitingSession';
        }
      }
      attachments.restore(List.of(files), states);
    }
    input.addListener(_inputChanged);
    transport.session.recovered.addListener(_recovered);
    transport.session.degraded.addListener(_connectionChanged);
  }
  final ComposerStore store;
  late final ComposerUsage usage;
  late final ComposerAttachments attachments;
  late final ComposerReferences references;
  String? _attachmentSessionId;
  Future<String>? _attachmentSessionPending;
  ConversationSubscription? _attachmentSubscription;
  Map<String, dynamic>? _attachmentConfig;
  bool _attachmentPromotionPending = false;
  final ConversationTransport transport;
  final String? deviceId;
  final String workspaceKey;
  String? sessionId;
  final input = ComposerInput();
  String get key => composerKey(deviceId, workspaceKey, sessionId);
  ConversationState? _state;
  ConversationState? get state => _state;
  WorkspacePrep? prep;
  ComposerOptions get options => ComposerOptions(prep);
  bool preparing = false;
  bool pickingAttachments = false;
  bool _repreparingAttachments = false;
  bool get preparingAttachments =>
      pickingAttachments || _repreparingAttachments;
  bool sending = false;
  bool _preparingSubmission = false;
  bool _pendingReceipt = false;
  bool stopping = false;
  bool queueBusy = false;
  ComposerFailure? failure;
  String? reasonCode;
  String? lastDelivery;
  List<String>? confirmationIds;
  bool _disposed = false;
  int _epoch = 0;
  int _prepGeneration = 0;
  int _configFloor = 0;
  int? _inFlightConfigEpoch;
  bool _awaitingSnapshot = false;
  Map<String, dynamic>? _stopProjection;
  Map<String, dynamic> _confirmed;
  final _intents = <_ConfigIntent>[];
  bool get _oldConfigPending =>
      _inFlightConfigEpoch != null && _inFlightConfigEpoch != _epoch;
  bool get configuring => _intents.isNotEmpty || _oldConfigPending;
  bool get connected => !_disposed && transport.session.degraded.value == null;
  bool get ready =>
      connected &&
      (sessionId == null || (!_awaitingSnapshot && _state?.ready == true));
  bool get _configurationReady =>
      ready && !sending && !queueBusy && !_oldConfigPending && prep != null;
  bool get canConfigureModel =>
      _configurationReady &&
      !_preparingSubmission &&
      (sessionId == null || allowed('switchModelConfig'));
  bool get canConfigureMode => _configurationReady && !_preparingSubmission;
  bool get draftConfigurationAvailable {
    if (sessionId != null) return true;
    if (_confirmed['model'] != null && options.model(_confirmed) == null) {
      return false;
    }
    if (_confirmed['mode'] != null &&
        !options.modes.any((o) => o.value == _confirmed['mode'])) {
      return false;
    }
    final thought = _confirmed['thought'];
    return thought == null ||
        thought == '' ||
        options.levels(_confirmed).contains(thought);
  }

  bool allowed(String capability) =>
      (_state?.snapshot?['availability'] as Map?)?[capability] is Map &&
      ((_state!.snapshot!['availability'] as Map)[capability]
              as Map)['allowed'] ==
          true;

  Map<String, dynamic> get config {
    var value = Map<String, dynamic>.of(_confirmed);
    for (final intent in _intents) {
      value = _applyIntent(intent, value) ?? value;
    }
    return value;
  }

  String get routing => _state?.inputRoutingMode ?? 'startNow';
  bool get isRunning => _state?.isRunning ?? false;
  bool get serverStopping =>
      _state?.control?['stopState'] == 'stopping' ||
      (_stopProjection != null && identical(_stopProjection, _state?.snapshot));
  bool get canSend =>
      ready &&
      !sending &&
      !_preparingSubmission &&
      !configuring &&
      !queueBusy &&
      !preparing &&
      (sessionId != null || prep != null) &&
      draftConfigurationAvailable &&
      routing != 'reject' &&
      (input.text.trim().isNotEmpty || attachments.items.isNotEmpty) &&
      !attachments.pending &&
      !preparingAttachments &&
      !composing;
  bool get composing =>
      input.value.composing.isValid && !input.value.composing.isCollapsed;
  bool get canStop =>
      ready && !stopping && !serverStopping && _state?.canStop == true;
  List<Map<String, dynamic>> get queue => _state?.queueItems ?? [];
  bool get canEditQueue =>
      ready && !sending && !configuring && !queueBusy && allowed('queueEdit');
  bool get canSendQueued =>
      ready &&
      !sending &&
      !configuring &&
      !queueBusy &&
      allowed('sendQueuedNow');

  void _notify() {
    if (_disposed) return;
    usage.selectProvider(config['provider'] as String?);
    references.updateScope();
    store.changed();
    notifyListeners();
  }

  void _usageChanged() {
    if (!_disposed) notifyListeners();
  }

  void _attachmentsChanged() {
    if (_disposed) return;
    if (attachments.items.isEmpty) {
      store.attachmentDrafts.remove(key);
    } else {
      store.attachmentDrafts[key] =
          attachments.items.map((e) => e.file).toList();
    }
    _notify();
  }

  Future<String> _ensureAttachmentSession() {
    if (sessionId != null) return Future.value(sessionId);
    return _attachmentSessionPending ??= () async {
      final config = Map<String, dynamic>.from(_confirmed);
      final id = _attachmentSessionId ??
          await transport.createSession(workspaceKey, config: config);
      if (_disposed) {
        if (store.durable) {
          store.retainProvisional(key, id, config);
        } else {
          unawaited(transport
              .sendCommand(id, 'deleteSession', {}).catchError((_) => null));
        }
        throw StateError('composer disposed');
      }
      _attachmentSessionId = id;
      _attachmentConfig ??= config;
      store.changed();
      await store.flush();
      _attachmentSubscription ??= await transport.subscribe(id);
      return id;
    }()
        .whenComplete(() => _attachmentSessionPending = null);
  }

  Future<void> _syncAttachmentConfig() async {
    await _ensureAttachmentSession();
    final id = _attachmentSessionId!;
    final state = _attachmentSubscription?.state;
    if (state != null && !state.ready) {
      final ready = Completer<void>();
      void changed() {
        if (state.ready && !ready.isCompleted) ready.complete();
      }

      state.addListener(changed);
      changed();
      try {
        await ready.future.timeout(const Duration(seconds: 30));
      } finally {
        state.removeListener(changed);
      }
    }
    final old = _attachmentConfig ?? {};
    if (['provider', 'model', 'thought']
        .any((key) => old[key] != _confirmed[key])) {
      final ack = await transport.switchModelConfig(id,
          provider: _confirmed['provider'] as String,
          model: _confirmed['model'] as String,
          thought: _confirmed['thought'] as String? ?? '');
      if (!_accepted(ack, noop: true)) {
        throw StateError('attachment model configuration rejected');
      }
    }
    if (old['mode'] != _confirmed['mode'] && _confirmed['mode'] is String) {
      final ack = await transport.switchCollaborationMode(
          id, _confirmed['mode'] as String);
      if (!_accepted(ack, noop: true)) {
        throw StateError('attachment mode configuration rejected');
      }
    }
    _attachmentConfig = Map.of(_confirmed);
  }

  Map<String, dynamic> get recoveryState => {
        'uncertain': _pendingReceipt ||
            failure == ComposerFailure.uncertain ||
            _attachmentSessionId != null && _attachmentPromotionPending,
        if (failure == ComposerFailure.send) 'failure': 'send',
        if (_attachmentSessionId != null)
          'provisionalSessionId': _attachmentSessionId,
        if (_attachmentConfig != null) 'provisionalConfig': _attachmentConfig,
        'attachments': [for (final entry in attachments.items) entry.toJson()],
      };
  bool beginAttachmentPick() {
    if (_disposed || preparingAttachments || sending || _preparingSubmission) {
      return false;
    }
    pickingAttachments = true;
    _notify();
    return true;
  }

  void finishAttachmentPick(List<PickedAttachment> files) {
    if (_disposed) {
      store.queuePickedFiles(key, files);
      return;
    }
    pickingAttachments = false;
    attachments.add(files);
    _notify();
  }

  bool get canReprepareAttachments =>
      !_disposed &&
      !sending &&
      !_preparingSubmission &&
      !preparingAttachments &&
      !attachments.busy &&
      attachments.items.isNotEmpty &&
      failure == ComposerFailure.send &&
      !_attachmentPromotionPending;

  Future<bool> reprepareAttachments() async {
    if (!canReprepareAttachments) return false;
    _repreparingAttachments = true;
    _notify();
    try {
      if (sessionId == null) {
        await _attachmentSubscription?.dispose();
        if (_disposed) return false;
        _attachmentSubscription = null;
        _attachmentSessionId = null;
        _attachmentConfig = null;
      }
      store.changed();
      await store.flush();
      if (_disposed) return false;
      failure = null;
      attachments.restartUploads();
      return true;
    } catch (_) {
      return false;
    } finally {
      _repreparingAttachments = false;
      _notify();
    }
  }

  void _inputChanged() {
    if (input.text.isEmpty) {
      store.drafts.remove(key);
      store.inputSnapshots.remove(key);
    } else {
      store.drafts[key] = input.markdown;
      store.inputSnapshots[key] = input.snapshot;
    }
    _notify();
  }

  void bind(ConversationState state) {
    if (identical(_state, state)) {
      _stateChanged();
      return;
    }
    _state?.removeListener(_stateChanged);
    _state = state;
    state.addListener(_stateChanged);
    _stateChanged();
  }

  void unbind(ConversationState? state) {
    if (!identical(_state, state)) return;
    _state?.removeListener(_stateChanged);
    _state = null;
  }

  void _stateChanged() {
    final state = _state;
    if (state?.ready == true) _awaitingSnapshot = false;
    if (state?.ready == true &&
        state!.revision >= _configFloor &&
        state.config != null) {
      _confirmed = Map.of(state.config!);
    }
    _notify();
  }

  Future<void> loadOptions({bool refresh = false}) async {
    final generation = ++_prepGeneration;
    preparing = true;
    _notify();
    try {
      final result = await transport.prepareWorkspace(refresh: refresh);
      if (_disposed || generation != _prepGeneration) return;
      prep = result;
      if (sessionId == null) {
        // Defaults fill missing values only. Reconnect is read-only.
        _confirmed = {...options.defaults(), ..._confirmed};
        store.saveDraftConfig(this, _confirmed);
      }
      if (failure == ComposerFailure.preparation) failure = null;
    } catch (_) {
      if (_disposed || generation != _prepGeneration) return;
      failure = ComposerFailure.preparation;
    } finally {
      if (!_disposed && generation == _prepGeneration) {
        preparing = false;
        _notify();
      }
    }
  }

  void _connectionChanged() {
    if (!connected) _awaitingSnapshot = true;
    _notify();
  }

  void _recovered() {
    usage.invalidate();
    references.invalidate();
    _epoch++;
    _awaitingSnapshot = sessionId != null;
    _stopProjection = null;
    _configFloor = 0;
    for (final intent in _intents) {
      intent.done.complete(false);
    }
    if (_intents.isNotEmpty) failure = ComposerFailure.configuration;
    _intents.clear();
    unawaited(loadOptions(refresh: true));
  }

  Future<bool> selectModel(String value) =>
      _enqueue(_ConfigIntent('model', value));
  Future<bool> selectMode(String value) =>
      _enqueue(_ConfigIntent('mode', value));
  Future<bool> selectThought(String value) =>
      _enqueue(_ConfigIntent('thought', value,
          provider: config['provider'] as String?,
          model: config['model'] as String?));

  Map<String, dynamic>? _applyIntent(
      _ConfigIntent intent, Map<String, dynamic> base) {
    if (intent.kind == 'mode') {
      return options.modes.any((o) => o.value == intent.value)
          ? {...base, 'mode': intent.value}
          : null;
    }
    if (intent.kind == 'model') {
      final value =
          options.models.where((o) => o.value == intent.value).firstOrNull;
      return value == null ? null : options.selectModel(value, base);
    }
    if (base['provider'] != intent.provider ||
        base['model'] != intent.model ||
        !options.levels(base).contains(intent.value)) {
      return null;
    }
    return {...base, 'thought': intent.value};
  }

  Future<bool> _enqueue(_ConfigIntent intent, {bool forSubmission = false}) {
    final allowed = intent.kind == 'mode' && forSubmission
        ? _configurationReady
        : intent.kind == 'mode'
            ? canConfigureMode
            : canConfigureModel;
    if (!allowed || _applyIntent(intent, config) == null) {
      return Future.value(false);
    }
    failure = null;
    final start = _intents.isEmpty;
    _intents.add(intent);
    _notify();
    if (start) unawaited(_drain(_epoch));
    return intent.done.future;
  }

  Future<void> _drain(int epoch) async {
    while (!_disposed && epoch == _epoch && _intents.isNotEmpty) {
      final intent = _intents.first;
      final next = _applyIntent(intent, _confirmed);
      var success = false;
      try {
        if (next == null ||
            !ready ||
            (intent.kind != 'mode' &&
                sessionId != null &&
                !allowed('switchModelConfig'))) {
          throw StateError('configuration-unavailable');
        }
        if (sessionId == null) {
          _confirmed = next;
          store.saveDraftConfig(this, next);
        } else {
          dynamic ack;
          _inFlightConfigEpoch = epoch;
          try {
            ack = intent.kind == 'mode'
                ? await transport.switchCollaborationMode(
                    sessionId!, intent.value)
                : await transport.switchModelConfig(sessionId!,
                    provider: next['provider'] as String,
                    model: next['model'] as String,
                    thought: next['thought'] as String? ?? '');
          } finally {
            if (_inFlightConfigEpoch == epoch) _inFlightConfigEpoch = null;
            _notify();
          }
          if (_disposed || epoch != _epoch) return;
          if (!_accepted(ack, noop: true)) {
            throw StateError('configuration-rejected');
          }
          final revision = ack is Map ? ack['revisionAtDecision'] : null;
          _configFloor = revision is num
              ? revision.toInt() + 1
              : (_state?.revision ?? 0) + 1;
          if ((_state?.revision ?? 0) < _configFloor) {
            _confirmed = next;
          } else {
            _confirmed = Map.of(_state!.config ?? next);
          }
        }
        success = true;
      } catch (_) {
        if (_disposed || epoch != _epoch) return;
        failure = ComposerFailure.configuration;
      }
      _intents.removeAt(0);
      if (!intent.done.isCompleted) intent.done.complete(success);
      _notify();
    }
  }

  bool _accepted(dynamic ack, {bool noop = false}) {
    if (ack is Map &&
        (ack['status'] == 'accepted' ||
            ack['status'] == 'duplicate' ||
            (noop && ack['status'] == 'noop'))) {
      return true;
    }
    final code = ack is Map ? ack['reasonCode'] : null;
    reasonCode =
        code is String && RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(code)
            ? code
            : null;
    return false;
  }

  Future<ComposerSendResult> send({String? heldQueueDisposition}) async {
    if (!canSend) return ComposerSendResult.blocked;
    _preparingSubmission = true;
    _notify();
    try {
      return await _submit(heldQueueDisposition: heldQueueDisposition);
    } finally {
      _preparingSubmission = false;
      _notify();
    }
  }

  Future<ComposerSendResult> _submit({String? heldQueueDisposition}) async {
    final original = input.text;
    final originalMarkdown = input.markdown;
    var wireText = originalMarkdown.trim();
    final special = parseComposerCommand(wireText,
        hasContext:
            attachments.items.isNotEmpty || input.contextReferenceCount > 0);
    if (special?.kind == ComposerCommandKind.invalid) {
      failure = ComposerFailure.command;
      _notify();
      return ComposerSendResult.blocked;
    }
    if (special?.kind == ComposerCommandKind.plan) {
      if (!await _enqueue(_ConfigIntent('mode', 'plan'), forSubmission: true)) {
        return ComposerSendResult.failed;
      }
      if (special!.text.isEmpty) {
        if (input.text == original && input.markdown == originalMarkdown) {
          input.clear();
        }
        return ComposerSendResult.sent;
      }
      wireText = special.text;
    }
    final ids = queue.map((e) => '${e['queueItemId']}').toList();
    if (heldQueueDisposition == null &&
        routing == 'choice' &&
        special?.kind != ComposerCommandKind.compact &&
        special?.kind != ComposerCommandKind.resumeGoal) {
      confirmationIds = ids;
      _notify();
      return ComposerSendResult.confirmationRequired;
    }
    if (heldQueueDisposition != null &&
        (confirmationIds == null || !listEquals(ids, confirmationIds))) {
      confirmationIds = ids;
      failure = ComposerFailure.queueChanged;
      _notify();
      return ComposerSendResult.confirmationRequired;
    }
    final sentAttachments = attachments.descriptors;
    final sentAttachmentIds = attachments.items.map((e) => e.id).toSet();
    final epoch = _epoch;
    sending = true;
    _pendingReceipt = true;
    failure = null;
    reasonCode = null;
    _notify();
    try {
      await store.flush();
      if (special != null && special.kind != ComposerCommandKind.plan) {
        final target = sessionId ?? await _ensureAttachmentSession();
        if (sessionId == null) {
          await _syncAttachmentConfig();
          _attachmentPromotionPending = true;
        }
        final ack = switch (special.kind) {
          ComposerCommandKind.compact => await transport.compact(target),
          ComposerCommandKind.resumeGoal => await transport.resumeGoal(target),
          ComposerCommandKind.goal => await transport.sendGoalCommand(
              target, special.text,
              displayText: special.displayText,
              heldQueueDisposition: heldQueueDisposition,
              expectedHeldQueueItemIds:
                  heldQueueDisposition == null ? null : ids),
          _ => throw StateError('invalid composer command'),
        };
        if (_disposed) return ComposerSendResult.failed;
        if (!_accepted(ack, noop: true)) {
          throw StateError('composer command rejected');
        }
        if (sessionId == null) {
          await _attachmentSubscription?.dispose();
          _attachmentSubscription = null;
          _attachmentSessionId = null;
          store.promote(this, target);
          sessionId = target;
        }
      } else if (sessionId == null) {
        String id;
        if (_attachmentSessionId != null) {
          await _syncAttachmentConfig();
          id = _attachmentSessionId!;
          _attachmentPromotionPending = true;
          final ack = await transport.sendText(id, wireText,
              attachments: sentAttachments);
          if (!_accepted(ack)) {
            _attachmentPromotionPending = false;
            throw StateError('attachment first input rejected');
          }
          await _attachmentSubscription?.dispose();
          _attachmentSubscription = null;
          _attachmentSessionId = null;
        } else {
          id = await transport
              .createSession(workspaceKey, firstText: wireText, config: {
            for (final field in [
              'provider',
              'model',
              'thought',
              'mode',
              'followupMode'
            ])
              if (_confirmed.containsKey(field)) field: _confirmed[field]
          });
        }
        if (_disposed) return ComposerSendResult.failed;
        store.promote(this, id);
        sessionId = id;
        // firstInput already delivered the text. No sendText follows creation.
      } else {
        final ack = await transport.sendText(sessionId!, wireText,
            attachments: sentAttachments,
            heldQueueDisposition: heldQueueDisposition,
            expectedHeldQueueItemIds:
                heldQueueDisposition == null ? null : ids);
        if (_disposed) return ComposerSendResult.failed;
        if (!_accepted(ack)) {
          if (ack is Map &&
              ack['reasonCode'] == 'guard.heldQueueConfirmationStale') {
            _pendingReceipt = false;
            confirmationIds = queue.map((e) => '${e['queueItemId']}').toList();
            return ComposerSendResult.confirmationRequired;
          }
          throw StateError('send-rejected');
        }
        lastDelivery =
            ack['result'] is Map ? ack['result']['delivery'] as String? : null;
      }
      _pendingReceipt = false;
      if (input.text == original && input.markdown == originalMarkdown) {
        input.clear();
      }
      attachments.accepted(sentAttachmentIds);
      _inputChanged();
      confirmationIds = null;
      // Once accepted remotely, a local save failure is not a failed send.
      await store.flush().catchError((_) {});
      return ComposerSendResult.sent;
    } on TimeoutException {
      if (!_disposed) failure = ComposerFailure.uncertain;
      return ComposerSendResult.failed;
    } catch (_) {
      _pendingReceipt = false;
      if (!_disposed) {
        failure =
            epoch == _epoch ? ComposerFailure.send : ComposerFailure.uncertain;
      }
      return ComposerSendResult.failed;
    } finally {
      if (!_disposed) {
        sending = false;
        _notify();
      }
    }
  }

  Future<bool> stop() async {
    if (!canStop || sessionId == null) return false;
    final works = _state?.control?['activeWorks'];
    final execution = works is List
        ? works
            .whereType<Map>()
            .map((e) => e['foregroundExecutionId'])
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .firstOrNull
        : null;
    stopping = true;
    final projection = _state?.snapshot;
    failure = null;
    _notify();
    try {
      final ack = await transport.stop(sessionId!,
          expectedForegroundExecutionId: execution);
      if (_disposed) return false;
      if (!_accepted(ack, noop: true)) throw StateError('stop-rejected');
      _stopProjection = projection;
      return true;
    } catch (_) {
      if (!_disposed) failure = ComposerFailure.stop;
      return false;
    } finally {
      if (!_disposed) {
        stopping = false;
        _notify();
      }
    }
  }

  Future<bool> queueAction(String action, {String? id, bool? autoDrain}) async {
    if (!(action == 'sendQueuedNow' ? canSendQueued : canEditQueue) ||
        sessionId == null) {
      return false;
    }
    if (id != null &&
        !queue.any((e) =>
            e['queueItemId'] == id &&
            (e['dispatch'] as Map?)?['state'] == 'queued')) {
      return false;
    }
    queueBusy = true;
    failure = null;
    _notify();
    try {
      final ack = switch (action) {
        'deleteQueueItem' => await transport.deleteQueueItem(sessionId!, id!),
        'sendQueuedNow' => await transport.sendQueuedNow(sessionId!, id!),
        'setAutoDrain' => await transport.setAutoDrain(sessionId!, autoDrain!),
        _ => throw StateError('unknown-queue-action'),
      };
      if (_disposed) return false;
      if (!_accepted(ack, noop: true)) throw StateError('queue-rejected');
      // Keep server projection authoritative; reserved/promoting entries are locked.
      return true;
    } catch (_) {
      if (!_disposed) failure = ComposerFailure.queue;
      return false;
    } finally {
      if (!_disposed) {
        queueBusy = false;
        _notify();
      }
    }
  }

  void dismissFailure() {
    failure = null;
    reasonCode = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _prepGeneration++;
    for (final intent in _intents) {
      if (!intent.done.isCompleted) intent.done.complete(false);
    }
    _intents.clear();
    _state?.removeListener(_stateChanged);
    transport.session.recovered.removeListener(_recovered);
    transport.session.degraded.removeListener(_connectionChanged);
    usage.dispose();
    references.dispose();
    attachments.dispose();
    unawaited(_attachmentSubscription?.dispose());
    if (_attachmentSessionId != null && !_attachmentPromotionPending) {
      final retain = store.durable &&
          (input.text.isNotEmpty || attachments.items.isNotEmpty);
      if (!retain) {
        unawaited(transport.sendCommand(_attachmentSessionId!, 'deleteSession',
            {}).catchError((_) => null));
      }
    }
    input.dispose();
    super.dispose();
  }
}
