import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../protocol/terminal.dart';
import '../state/client_preferences.dart';
import '../state/terminal_sessions.dart';
import '../state/terminal_session.dart';
import 'official_icons.dart';
import 'shell/shell_layout.dart';
import 'terminal_renderer.dart';
import 'theme.dart';

class TerminalPanel extends StatefulWidget {
  final TerminalClient client;
  final String cwd;
  final bool visible;
  final TerminalSessionController? controller;
  final TerminalWorkspaceSessions? workspace;

  const TerminalPanel({
    super.key,
    required this.client,
    required this.cwd,
    required this.visible,
    this.controller,
    this.workspace,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  late TerminalSessionController _controller;
  TerminalSessionController? _boundController;
  TerminalSessionController? _fallbackController;
  late final bool _ownsController;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  bool Function(KeyEvent)? _hardwareKeyHandler;
  final _renderers = <TerminalSessionController, TerminalOutputRenderer>{};

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null && widget.workspace == null;
    widget.workspace?.addListener(_onWorkspaceChanged);
    _bindController();
    _hardwareKeyHandler = _onHardwareKey;
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler!);
    if (widget.visible) _scheduleOpen();
  }

  @override
  void didUpdateWidget(TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _scheduleOpen();
    }
    if (widget.workspace != oldWidget.workspace ||
        widget.controller != oldWidget.controller) {
      if (widget.workspace != null) {
        for (final controller in _renderers.keys.toList()) {
          if (!widget.workspace!.controllers.contains(controller)) {
            _renderers.remove(controller)?.dispose();
          }
        }
      }
      _bindController();
    }
    if (widget.cwd != oldWidget.cwd && _ownsController) {
      unawaited(_controller.close());
    }
  }

  @override
  void dispose() {
    if (_hardwareKeyHandler != null) {
      HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler!);
    }
    _inputFocus.dispose();
    widget.workspace?.removeListener(_onWorkspaceChanged);
    // close() can notify synchronously before its first await, even when
    // no remote terminal was created. Detach the view before starting it.
    _boundController?.removeListener(_onSessionChanged);
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    _renderers.clear();
    if (_ownsController) {
      unawaited(_shutdown());
    }
    _input.dispose();
    super.dispose();
  }

  Future<void> _shutdown() async {
    final controller = _fallbackController;
    if (controller != null) {
      _renderers.remove(controller)?.dispose();
      await controller.close();
      controller.removeListener(_onSessionChanged);
      controller.dispose();
    }
  }

  void _bindController() {
    final controller = widget.controller ??
        widget.workspace?.activeController ??
        (_fallbackController ??=
            TerminalSessionController(client: widget.client, cwd: widget.cwd));
    if (identical(_boundController, controller)) return;
    _boundController?.removeListener(_onSessionChanged);
    _boundController = controller;
    _controller = controller;
    controller.addListener(_onSessionChanged);
  }

  void _scheduleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.visible) return;
      final binding = _binding;
      if (_controller.status == TerminalSessionStatus.idle) {
        _controller.cols = binding.terminal.viewWidth;
        _controller.rows = binding.terminal.viewHeight;
      }
      unawaited(_controller.open());
    });
  }

  TerminalOutputRenderer get _binding => _renderers.putIfAbsent(
      _controller, () => TerminalOutputRenderer(_controller));

  void _onWorkspaceChanged() {
    if (!mounted) return;
    _bindController();
    setState(() {});
    if (widget.visible) _scheduleOpen();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _send(String data) async {
    if (data.isEmpty) return;
    try {
      await _controller.write(data);
    } catch (_) {
      // The controller publishes a retryable failed state for the panel.
    }
  }

  Future<void> _sendLine() async {
    final text = _input.text;
    _input.clear();
    await _send('$text\r');
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.visible ||
        !_inputFocus.hasFocus ||
        !_controller.canInput) {
      return false;
    }
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed) {
      final code = switch (key) {
        LogicalKeyboardKey.keyC => '\u0003',
        LogicalKeyboardKey.keyD => '\u0004',
        LogicalKeyboardKey.keyZ => '\u001a',
        LogicalKeyboardKey.keyL => '\u000c',
        _ => null,
      };
      if (code != null) {
        unawaited(_send(code));
        return true;
      }
      return false;
    }
    final sequence = switch (key) {
      LogicalKeyboardKey.escape => '\u001b',
      LogicalKeyboardKey.arrowUp => '\u001b[A',
      LogicalKeyboardKey.arrowDown => '\u001b[B',
      LogicalKeyboardKey.arrowRight => '\u001b[C',
      LogicalKeyboardKey.arrowLeft => '\u001b[D',
      LogicalKeyboardKey.tab => '\t',
      _ => null,
    };
    if (sequence == null) return false;
    unawaited(_send(sequence));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return LayoutBuilder(builder: (context, constraints) {
      // The normal drawer has enough room to keep the terminal viewport
      // expanded above the controls. On a keyboard-compressed landscape
      // viewport, keep the same controls in a vertical scroll region so the
      // input and touch shortcuts remain reachable without a RenderFlex
      // overflow or remounting the terminal session.
      final compact =
          constraints.hasBoundedHeight && constraints.maxHeight < 220;
      final terminalView = Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: ink.background,
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(ZRadius.lg),
        ),
        child: TerminalView(
          _binding.terminal,
          key: ValueKey(_controller),
          theme: terminalThemeFor(
            Theme.of(context).colorScheme.brightness,
            _controller.theme,
          ),
          textStyle: terminalStyleFor(
            fontFamily: _controller.fontFamily,
            fontSize: _controller.fontSize,
          ),
          readOnly: !_controller.canInput,
          deleteDetection: true,
          autofocus: _controller.canInput,
        ),
      );
      final controls = Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _ControlButton(
                  label: 'Ctrl+C',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u0003')),
                ),
                _ControlButton(
                  label: 'Ctrl+D',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u0004')),
                ),
                _ControlButton(
                  label: 'Ctrl+Z',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u001a')),
                ),
                _ControlButton(
                  label: 'Ctrl+L',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u000c')),
                ),
                _ControlButton(
                  label: 'Esc',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u001b')),
                ),
                _ControlButton(
                  label: '↑',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u001b[A')),
                ),
                _ControlButton(
                  label: '↓',
                  enabled: _controller.canInput,
                  onTap: () => unawaited(_send('\u001b[B')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    enabled: _controller.canInput,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 4,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: uiText(context, '输入终端内容', 'Terminal input'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_sendLine()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _controller.canInput
                      ? () => unawaited(_sendLine())
                      : null,
                  child: Text(uiText(context, '发送', 'Send')),
                ),
              ],
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                LucideIcon('terminal', size: 14, color: ink.subtlest),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _statusLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink.subtlest),
                  ),
                ),
                if (_controller.status == TerminalSessionStatus.ready)
                  TextButton(
                    onPressed: () => unawaited(_controller.close()),
                    child: Text(uiText(context, '关闭', 'Close')),
                  ),
                if (_controller.status == TerminalSessionStatus.exited ||
                    _controller.status == TerminalSessionStatus.failed)
                  TextButton(
                    onPressed: () => unawaited(_controller.open()),
                    child: Text(uiText(context, '新建终端', 'New terminal')),
                  ),
              ],
            ),
          ),
          if (compact)
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('terminal-compact-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 64, child: terminalView),
                    controls,
                  ],
                ),
              ),
            )
          else ...[
            Expanded(child: terminalView),
            controls,
          ],
        ],
      );
    });
  }

  String _statusLabel() {
    switch (_controller.status) {
      case TerminalSessionStatus.idle:
        return uiText(context, '终端未打开', 'Terminal closed');
      case TerminalSessionStatus.creating:
        return uiText(context, '正在打开终端…', 'Opening terminal…');
      case TerminalSessionStatus.ready:
        return _controller.shellLabel ??
            uiText(context, '终端已就绪', 'Terminal ready');
      case TerminalSessionStatus.failed:
        return uiText(context, '终端打开失败', 'Could not open terminal');
      case TerminalSessionStatus.exited:
        return '[Process exited ${_controller.exitCode ?? ''}]'.trim();
    }
  }
}

/// Official remote hosts terminals in a bottom drawer with a workspace-named
/// tab bar: "终端" label, tabs with close on the active tab, "+" to add and a
/// drawer close button on the right.
class TerminalDrawer extends StatefulWidget {
  final TerminalClient client;
  final String cwd;
  final bool visible;
  final TerminalWorkspaceSessions? workspace;
  final VoidCallback? onCloseDrawer;

  const TerminalDrawer({
    super.key,
    required this.client,
    required this.cwd,
    required this.visible,
    this.workspace,
    this.onCloseDrawer,
  });

  @override
  State<TerminalDrawer> createState() => _TerminalDrawerState();
}

class _TerminalDrawerState extends State<TerminalDrawer> {
  @override
  void initState() {
    super.initState();
    widget.workspace?.addListener(_onWorkspaceChanged);
  }

  @override
  void didUpdateWidget(TerminalDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspace != oldWidget.workspace) {
      oldWidget.workspace?.removeListener(_onWorkspaceChanged);
      widget.workspace?.addListener(_onWorkspaceChanged);
    }
  }

  @override
  void dispose() {
    widget.workspace?.removeListener(_onWorkspaceChanged);
    super.dispose();
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final workspace = widget.workspace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ink.border))),
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(uiText(context, '终端', 'Terminal'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
            ),
            if (workspace != null)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(children: [
                    for (var index = 0;
                        index < workspace.controllers.length;
                        index++)
                      _TerminalTab(
                        label: workspace.controllers[index].shellLabel ??
                            uiText(context, '终端 ${index + 1}',
                                'Terminal ${index + 1}'),
                        selected: workspace.activeIndex == index,
                        onTap: () => workspace.activate(index),
                        onClose: workspace.activeIndex == index
                            ? () => unawaited(workspace.closeAt(index))
                            : null,
                      ),
                  ]),
                ),
              )
            else
              const Spacer(),
            if (workspace != null && workspace.canAdd)
              ShellIconButton(
                  icon: 'plus',
                  label: uiText(context, '新建终端标签', 'New terminal tab'),
                  onPressed: () => workspace.add()),
            if (widget.onCloseDrawer != null)
              ShellIconButton(
                  icon: 'x',
                  label: uiText(context, '关闭终端抽屉', 'Close terminal drawer'),
                  onPressed: widget.onCloseDrawer!),
          ]),
        ),
        Expanded(
          child: TerminalPanel(
            client: widget.client,
            cwd: widget.cwd,
            visible: widget.visible,
            workspace: workspace,
          ),
        ),
      ],
    );
  }
}

class _TerminalTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _TerminalTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? ink.hover : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side:
                BorderSide(color: selected ? ink.border : Colors.transparent)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? ink.text : ink.subtlest)),
              ),
              if (onClose != null)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: const EdgeInsets.all(4),
                    iconSize: 12,
                    tooltip: uiText(context, '关闭终端标签', 'Close terminal tab'),
                    onPressed: onClose,
                    icon: LucideIcon('x', size: 12, color: ink.subtlest),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ControlButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      child: Text(label),
    );
  }
}
