import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_controller.dart';
import '../../state/composer_attachments.dart';
import '../../attachments/attachment_picker.dart';
import '../theme.dart';
import '../conversation_layout.dart';
import 'composer_toolbar.dart';
import 'composer_queue.dart';
import 'attachment_strip.dart';
import 'reference_panel.dart';
import '../voice_input_button.dart';
import '../voice_model_manager.dart';
import '../../voice/voice_transcriber_sherpa.dart';
import '../../state/voice_input.dart';
import '../../voice/voice_errors.dart';

class ComposerBar extends StatefulWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    this.onManageModels,
    @visibleForTesting this.voiceInput,
  });
  final ComposerController controller;
  final VoidCallback? onManageModels;
  @visibleForTesting
  final VoiceInputController? voiceInput;
  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  bool _wasComposing = false;
  bool _hovered = false;
  Timer? _commitGuard;
  VoiceInputController? _voice;
  bool _ownsVoice = true;
  @override
  void initState() {
    super.initState();
    widget.controller.input.addListener(_editingChanged);
    _focus.addListener(_focusChanged);
    _ensureVoice();
  }

  void _focusChanged() => setState(() {});

  @override
  void didUpdateWidget(ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.voiceInput != widget.voiceInput) {
      oldWidget.controller.input.removeListener(_editingChanged);
      widget.controller.input.addListener(_editingChanged);
      _wasComposing = false;
      _commitGuard?.cancel();
      _ensureVoice();
    }
  }

  void _ensureVoice() {
    final previous = _voice;
    if (previous != null) {
      if (_ownsVoice) {
        previous.dispose();
      } else if (previous.isBusy) {
        unawaited(previous.cancel());
      }
    }
    final provided = widget.voiceInput;
    if (provided != null && identical(provided.composer, widget.controller)) {
      _voice = provided;
      _ownsVoice = false;
      return;
    }
    _voice = VoiceInputController(
      composer: widget.controller,
      transcriber: SherpaVoiceTranscriber(),
    );
    _ownsVoice = true;
  }

  void _editingChanged() {
    final composing = widget.controller.composing;
    if (_wasComposing && !composing) {
      _commitGuard?.cancel();
      _commitGuard = Timer(const Duration(milliseconds: 150), () {});
    }
    _wasComposing = composing;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final references = widget.controller.references;
    if (event is KeyDownEvent &&
        references.open &&
        !widget.controller.composing) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        references.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        references
            .move(event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed &&
          _commitGuard?.isActive != true) {
        references.pick();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.controller.composing) return KeyEventResult.ignored;
    // Some desktop IMEs clear composing before delivering the confirming Enter.
    if (_commitGuard?.isActive == true) {
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      final value = widget.controller.input.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      widget.controller.input.value = TextEditingValue(
          text: value.text.replaceRange(selection.start, selection.end, '\n'),
          selection: TextSelection.collapsed(offset: selection.start + 1));
      return KeyEventResult.handled;
    }
    _send();
    return KeyEventResult.handled;
  }

  Future<void> _send({String? disposition}) async {
    final controller = widget.controller;
    final result = await controller.send(heldQueueDisposition: disposition);
    if (!mounted || result != ComposerSendResult.confirmationRequired) return;
    final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '处理待发队列', 'Queued messages')),
                content: Text(uiText(context, '当前仍有待发消息。发送这条消息时，保留还是清空队列？',
                    'There are queued messages. Keep or clear them when sending this message?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(context, 'keepQueueAndSend'),
                      child: Text(uiText(context, '保留并发送', 'Keep and send'))),
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(context, 'clearQueueAndSend'),
                      child: Text(uiText(context, '清空并发送', 'Clear and send'))),
                ]));
    if (!mounted || controller != widget.controller || choice == null) return;
    await _send(disposition: choice);
  }

  Future<void> _pickAttachments() async {
    final controller = widget.controller;
    if (!controller.beginAttachmentPick()) return;
    var files = <PickedAttachment>[];
    try {
      files = await pickAttachments();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(uiText(context, '无法读取附件，请重新选择',
                'Could not read attachments. Choose again.'))));
      }
    } finally {
      controller.finishAttachmentPick(files);
    }
    if (mounted && widget.controller == controller) _focus.requestFocus();
  }

  void _openVoiceModels() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: VoiceModelManager(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.input.removeListener(_editingChanged);
    _commitGuard?.cancel();
    _focus.dispose();
    if (_ownsVoice) _voice?.dispose();
    _voice = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        widget.controller.store.recovery,
        if (_voice != null) _voice,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final issue = controller.connectionIssue;
        final recoveryFailed = issue?.startsWith('reopen-failed:') == true;
        final status = !controller.connected
            ? recoveryFailed
                ? uiText(context, '工作区恢复失败，仍在尝试…',
                    'Workspace recovery failed; still trying…')
                : issue == 'user-disconnected' ||
                        issue == 'credentials-invalid' ||
                        issue == 'connection-failed' ||
                        issue == 'kicked'
                    ? uiText(context, '连接暂不可用', 'Connection unavailable')
                    : uiText(context, '正在恢复连接…', 'Reconnecting…')
            : controller.preparing
                ? uiText(context, '正在读取配置…', 'Loading configuration…')
                : controller.configuring
                    ? uiText(context, '正在切换配置…', 'Applying configuration…')
                    : controller.preparingAttachments
                        ? uiText(context, '正在准备附件…', 'Preparing attachments…')
                        : controller.stopping || controller.serverStopping
                            ? uiText(context, '正在停止…', 'Stopping…')
                            : controller.sending
                                ? uiText(context, '正在提交…', 'Submitting…')
                                : controller.routing == 'reject'
                                    ? uiText(context, '当前任务暂不接受输入',
                                        'Input is currently unavailable')
                                    : controller.isRunning
                                        ? switch (controller.routing) {
                                            'enqueue' => uiText(
                                                context,
                                                '处理中 · 新消息将加入队列',
                                                'Working · Messages will be queued'),
                                            'guide' => uiText(
                                                context,
                                                '处理中 · 新消息将引导当前任务',
                                                'Working · Messages will guide the task'),
                                            _ =>
                                              uiText(context, '处理中', 'Working'),
                                          }
                                        : null;
        // Scaffold removes viewInsets from its body MediaQuery while resizing
        // the body. Read the FlutterView metrics so the composer can detect a
        // genuinely short keyboard viewport without compacting tall layouts.
        final view = View.of(context);
        final viewHeight = view.physicalSize.height / view.devicePixelRatio;
        final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
        final compactForKeyboard =
            keyboardInset > 0 && viewHeight - keyboardInset < 320;
        return SafeArea(
            top: false,
            child: Padding(
                padding: EdgeInsets.only(
                    top: compactForKeyboard ? 0 : 8,
                    bottom: compactForKeyboard ? 0 : 16),
                child: ConversationColumn(
                    child: LayoutBuilder(
                        builder: (context, region) =>
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              if (controller.references.open)
                                ReferencePanel(
                                    references: controller.references,
                                    onPicked: _focus.requestFocus),
                              if (controller.queue.isNotEmpty)
                                ComposerQueue(controller: controller),
                              if (controller.prep != null &&
                                  !controller.draftConfigurationAvailable)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                        uiText(context, '所选配置已不可用，请重新选择',
                                            'Selected configuration is unavailable. Choose again.'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ink.diffRemoved))),
                              if (controller.failure != null)
                                _Failure(controller: controller),
                              if (controller.store.recovery?.failed == true)
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          uiText(context, '草稿尚未保存，请重试',
                                              'Draft not saved. Please retry.'),
                                          key: const ValueKey(
                                              'draft-save-error'),
                                          style: TextStyle(
                                              color: ink.diffRemoved,
                                              fontSize: 12))),
                                  TextButton(
                                      key: const ValueKey('draft-save-retry'),
                                      onPressed: () => controller.store
                                          .flush()
                                          .catchError((_) {}),
                                      child:
                                          Text(uiText(context, '重试', 'Retry'))),
                                ]),
                              if (status != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(status,
                                        key: const ValueKey('composer-status'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ink.subtlest))),
                              if (_voice?.phase == VoiceInputPhase.error)
                                _VoiceErrorBanner(
                                    voice: _voice!,
                                    onManageModels: _openVoiceModels),
                              if (_voice?.isBusy == true)
                                _VoiceStatusBanner(
                                    voice: _voice!,
                                    compact: compactForKeyboard),
                              if (controller.pickingAttachments)
                                TextButton(
                                    onPressed: cancelAttachmentPick,
                                    child: Text(uiText(context, '取消附件准备',
                                        'Cancel attachment preparation'))),
                              MouseRegion(
                                  onEnter: (_) =>
                                      setState(() => _hovered = true),
                                  onExit: (_) =>
                                      setState(() => _hovered = false),
                                  child: Container(
                                      key: const ValueKey('composer-surface'),
                                      decoration: BoxDecoration(
                                          color: ink.card,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: _focus.hasFocus || _hovered
                                                  ? ink.borderHover
                                                  : ink.border)),
                                      padding: EdgeInsets.all(
                                          compactForKeyboard ? 1 : 12),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (controller
                                                .attachments.items.isNotEmpty)
                                              AttachmentStrip(
                                                  attachments:
                                                      controller.attachments,
                                                  locked: controller.sending),
                                            TextField(
                                                key: const ValueKey(
                                                    'composer-input'),
                                                controller: controller.input,
                                                focusNode: _focus,
                                                minLines: 1,
                                                maxLines:
                                                    compactForKeyboard ? 1 : 6,
                                                keyboardType:
                                                    TextInputType.multiline,
                                                textInputAction:
                                                    TextInputAction.newline,
                                                textAlignVertical:
                                                    TextAlignVertical.top,
                                                style: TextStyle(
                                                    color: ink.text,
                                                    fontSize: 14,
                                                    height: compactForKeyboard
                                                        ? 1.2
                                                        : 1.5),
                                                decoration: InputDecoration(
                                                    constraints: BoxConstraints(
                                                        minHeight:
                                                            compactForKeyboard
                                                                ? 24
                                                                : 52),
                                                    hintText: uiText(context,
                                                        '输入消息…', 'Message…'),
                                                    hintStyle: TextStyle(
                                                        color: ink.subtlest),
                                                    border: InputBorder.none,
                                                    enabledBorder:
                                                        InputBorder.none,
                                                    focusedBorder:
                                                        InputBorder.none,
                                                    filled: false,
                                                    isDense: true,
                                                    contentPadding: EdgeInsets.only(
                                                        bottom:
                                                            compactForKeyboard
                                                                ? 0
                                                                : 12))),
                                            ComposerToolbar(
                                                controller: controller,
                                                containerWidth: region.maxWidth,
                                                onSend: _send,
                                                onAddAttachment:
                                                    _pickAttachments,
                                                voiceInput: _voice == null
                                                    ? null
                                                    : VoiceInputButton(
                                                        voice: _voice!,
                                                        onDone: () => _focus
                                                            .requestFocus(),
                                                      ),
                                                onTrigger: (symbol) {
                                                  controller.references
                                                      .insertTrigger(symbol);
                                                  _focus.requestFocus();
                                                },
                                                onManageModels:
                                                    widget.onManageModels),
                                          ]))),
                            ])))));
      });
}

class _VoiceErrorBanner extends StatelessWidget {
  const _VoiceErrorBanner({
    required this.voice,
    required this.onManageModels,
  });

  final VoiceInputController voice;
  final VoidCallback onManageModels;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final english = Localizations.localeOf(context).languageCode != 'zh';
    final message = voiceFailureMessage(voice.errorKind, english: english) ??
        voice.error ??
        uiText(context, '语音输入失败', 'Voice input failed');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: const ValueKey('voice-error'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ink.card,
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Text(message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: ink.diffRemoved)),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: voice.start,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(uiText(context, '重试', 'Retry')),
          ),
          if (voice.canManageModels)
            TextButton(
              onPressed: onManageModels,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(uiText(context, '模型管理', 'Models')),
            ),
        ]),
      ),
    );
  }
}

class _VoiceStatusBanner extends StatelessWidget {
  const _VoiceStatusBanner({required this.voice, this.compact = false});

  final VoiceInputController voice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final status = switch (voice.phase) {
      VoiceInputPhase.requesting =>
        uiText(context, '正在准备语音输入…', 'Preparing voice input…'),
      VoiceInputPhase.recording => uiText(context, '正在录音…', 'Listening…'),
      VoiceInputPhase.recognizing => uiText(context, '正在识别…', 'Recognizing…'),
      VoiceInputPhase.idle || VoiceInputPhase.error => '',
    };
    if (status.isEmpty) return const SizedBox.shrink();
    final preview = voice.partial;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 6),
      child: Container(
        key: const ValueKey('voice-status'),
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 1 : 6),
        decoration: BoxDecoration(
          color: ink.card,
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq, size: 18, color: ink.subtlest),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink.text),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  key: const ValueKey('composer-voice-cancel'),
                  onPressed: voice.cancel,
                  style: TextButton.styleFrom(
                    minimumSize: Size(0, compact ? 28 : 30),
                    tapTargetSize: compact
                        ? MaterialTapTargetSize.shrinkWrap
                        : MaterialTapTargetSize.padded,
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(uiText(context, '取消', 'Cancel')),
                ),
              ],
            ),
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Semantics(
                  label: uiText(context, '最新语音预览', 'Latest voice preview'),
                  child: Text(
                    preview,
                    key: const ValueKey('voice-preview'),
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      height: compact ? 1.2 : 1.35,
                      color: ink.text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.controller});
  final ComposerController controller;
  @override
  Widget build(BuildContext context) {
    final text = switch (controller.failure!) {
      ComposerFailure.preparation =>
        uiText(context, '配置读取失败，请重试', 'Could not load configuration. Retry.'),
      ComposerFailure.configuration => uiText(context, '配置未确认，保留已确认的选择',
          'Configuration was not confirmed. Kept the confirmed selection.'),
      ComposerFailure.send => uiText(context, '发送失败，草稿已保留，请重试',
          'Could not send. Your draft is preserved. Try again.'),
      ComposerFailure.uncertain => uiText(
          context,
          '未收到发送回执，草稿已保留。请先核对历史，避免重复发送。',
          'No send receipt. Draft preserved. Check history before retrying to avoid duplicates.'),
      ComposerFailure.stop => uiText(context, '停止未确认，请查看任务状态',
          'Stop was not confirmed. Check task status.'),
      ComposerFailure.queue => uiText(context, '队列操作未确认，请查看队列状态',
          'Queue action was not confirmed. Check its status.'),
      ComposerFailure.queueChanged => uiText(
          context, '队列已变化，请重新确认', 'The queue changed. Please confirm again.'),
      ComposerFailure.queueEditConflict => uiText(
          context,
          '请先发送或清空当前草稿，再编辑待发消息。',
          'Send or clear the current draft before editing a queued message.'),
      ComposerFailure.queueEditRestoreFailed => uiText(
          context,
          '未能把待发消息退回输入框。请重试。',
          "Couldn't return the queued message to the composer. Try again."),
      ComposerFailure.command => uiText(
          context,
          '请检查能力参数：目标需要正文，计划快捷指令不能附带上下文或附件。',
          'Check the command: goals require text; /plan does not accept context or attachments.'),
    };
    return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(text,
                    key: const ValueKey('composer-error'),
                    style: TextStyle(
                        fontSize: 12,
                        color: ZInk.of(Theme.of(context).colorScheme)
                            .diffRemoved))),
            IconButton(
                tooltip: controller.failure == ComposerFailure.preparation
                    ? uiText(context, '重试', 'Retry')
                    : uiText(context, '关闭', 'Dismiss'),
                onPressed: controller.failure == ComposerFailure.preparation
                    ? () => controller.loadOptions(refresh: true)
                    : controller.dismissFailure,
                icon: Icon(
                    controller.failure == ComposerFailure.preparation
                        ? Icons.refresh
                        : Icons.close,
                    size: 16)),
          ]),
          if (controller.canReprepareAttachments)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: controller.reprepareAttachments,
                    child: Text(uiText(
                        context, '重新准备附件', 'Prepare attachments again')))),
        ]));
  }
}
