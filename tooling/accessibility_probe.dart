import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:zcode_remote/ui/composer/composer_popover.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';

/// Standalone native QA entrypoint, without a Flutter test runner or connection.
/// Repeated UIAutomator clients must be able to re-enable an idle semantic tree.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = await const MethodChannel('zcode_remote/attachments')
      .invokeMapMethod<String, dynamic>('environment');
  if (environment?['packageName'] != 'com.zcoderemote.zcode_remote.qa') {
    throw StateError(
        'The accessibility probe requires the separate QA package.');
  }
  runApp(const MaterialApp(
      debugShowCheckedModeBanner: false, home: _AccessibilityProbe()));
}

class _AccessibilityProbe extends StatefulWidget {
  const _AccessibilityProbe();
  @override
  State<_AccessibilityProbe> createState() => _AccessibilityProbeState();
}

class _AccessibilityProbeState extends State<_AccessibilityProbe> {
  SemanticsHandle? _handle;
  var _counter = 0;
  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('语义树 QA · 无远程连接')),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('计数 $_counter'),
            ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const _SelectableLinkProbe())),
                child: const Text('SDK 可选链接对照')),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => _ConversationProbe())),
                child: const Text('长消息列表')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const _TaskProbe())),
                child: const Text('完整任务组合')),
            ElevatedButton(
                onPressed: () => setState(() => _counter++),
                child: const Text('增加计数')),
            ElevatedButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: const Text('普通弹窗'),
                            content: const Text('静态内容'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭弹窗'))
                            ])),
                child: const Text('普通弹窗')),
            Builder(
                builder: (context) => ElevatedButton(
                    onPressed: () => showComposerPopover(context,
                        child: Builder(
                            builder: (context) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭浮层'))))),
                    child: const Text('Composer 浮层'))),
            ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('普通页面')),
                            body: const Center(child: Text('静态正文'))))),
                child: const Text('打开页面')),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: () => setState(() {
                      if (_handle == null) {
                        _handle = RendererBinding.instance.ensureSemantics();
                      } else {
                        _handle!.dispose();
                        _handle = null;
                      }
                    }),
                child: Text(_handle == null ? '保持语义树：关' : '保持语义树：开')),
          ])));
}

class _SelectableLinkProbe extends StatefulWidget {
  const _SelectableLinkProbe();
  @override
  State<_SelectableLinkProbe> createState() => _SelectableLinkProbeState();
}

class _SelectableLinkProbeState extends State<_SelectableLinkProbe> {
  final link = TapGestureRecognizer()..onTap = (() {});
  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('SDK 可选链接对照')),
      body: Center(
          child: SelectableText.rich(TextSpan(children: [
        const TextSpan(text: '普通文本 '),
        TextSpan(text: '链接文字', recognizer: link),
        const TextSpan(text: ' 后续文本'),
      ]))));
}

class _ConversationProbe extends StatelessWidget {
  _ConversationProbe();
  final view = ConversationViewState();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('长消息列表')),
      body: ConversationViewport(
          view: view,
          ids: List.generate(100, (index) => '$index'),
          itemBuilder: (_, index) =>
              Text('消息 $index\n${'可变高度内容\n' * (1 + index % 9)}')));
}

class _TaskProbe extends StatefulWidget {
  const _TaskProbe();
  @override
  State<_TaskProbe> createState() => _TaskProbeState();
}

class _TaskProbeState extends State<_TaskProbe> {
  final bridge = FeatureBridge();
  var collapsed = false;
  @override
  void initState() {
    super.initState();
    bridge.channels.handler = (_, method, args) => switch (method) {
          'getCodingPlanResetStatus' => {
              'availableFiveHourResets': [],
              'availableWeekResets': [],
              'hasUnreadHistory': false
            },
          'requestCodingPlanResetOpportunity' => {'granted': false},
          _ => {},
        };
    final rows = <Map<String, dynamic>>[
      for (var i = 0; i < 8; i++) ...[
        {
          'kind': 'userInput',
          'rowId': i * 2 + 1,
          'text': '检查第 $i 个交互场景，保持原位置。'
        },
        {
          'kind': 'assistantText',
          'rowId': i * 2 + 2,
          'text': '已检查当前页面布局，支持 [参考文件](test.md)。\n\n'
              '| 项目 | 说明 |\n| --- | --- |\n| 视图 | 状态隔离 |\n| 返回 | 保留草稿 |\n\n'
              '- 任务面板保持原位置。\n- 检查变高内容。\n\n```dart\nfinal value = 42;\n```'
        }
      ]
    ];
    bridge.conversationTransport.states['task'] = ConversationState()
      ..applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'config': {
              ...composerSnapshotFixture['config'] as Map,
              'provider': 'builtin:bigmodel-coding-plan'
            },
            'usage': {
              'contextWindow': {'usedTokens': 140794, 'maxTokens': 1000000}
            },
            'rows': {'totalCount': rows.length, 'firstRowId': 1, 'window': rows}
          }
        }
      }, onGap: () {});
  }

  @override
  void dispose() {
    bridge.channels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceShellLayout(
      title: '完整任务组合',
      project: 'Synthetic',
      sidebar: ListView(children: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回诊断页')),
        const Text('侧栏任务')
      ]),
      conversation: ChatPage(
          session: bridge,
          scope: const {},
          workspaceKey: 'synthetic',
          sessionId: 'task',
          title: 'Synthetic',
          embedded: true),
      sidebarCollapsed: collapsed,
      onSidebarCollapsed: (value) => setState(() => collapsed = value));
}
