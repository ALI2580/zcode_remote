import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'package:zcode_remote/ui/shell/task_navigation.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';

class _IndexDevice extends FakeDeviceSession {
  _IndexDevice(super.params, super.bridge, this.initialTasks);
  final List<Map<String, dynamic>> initialTasks;
  @override
  List<Map<String, dynamic>> get taskIndex => initialTasks;
  @override
  int get taskIndexVersion => 1;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native task management uses scoped server acknowledgments',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    var revision = DateTime.now().millisecondsSinceEpoch;
    var server = <Map<String, dynamic>>[
      {
        'taskId': 'control',
        'title': '原始任务',
        'workspaceIdentity': 'workspace',
        'updatedAt': revision - 10
      },
      {
        'taskId': 'target',
        'title': '测试任务',
        'workspaceIdentity': 'workspace',
        'updatedAt': revision
      },
    ];
    final initial = [
      for (final task in server) Map<String, dynamic>.from(task)
    ];
    final bridge = FeatureBridge();
    var rejectPin = false;
    bridge.channels.handler = (_, method, args) {
      if (method == 'listTasks') return server;
      if (method == 'listPinnedTasks') {
        return server.where((t) => t['pinned'] == true).toList();
      }
      if (method == 'listArchivedTasks') {
        return server.where((t) => t['archived'] == true).toList();
      }
      final input = args.single as Map;
      final index = server.indexWhere((t) => t['taskId'] == input['taskId']);
      if (index < 0) throw StateError('unexpected synthetic task');
      if (method == 'setTaskPinned' && rejectPin) {
        throw StateError('synthetic rejected');
      }
      if (method == 'deleteTask') {
        server = server.where((t) => t['taskId'] != input['taskId']).toList();
      } else {
        server[index] = {
          ...server[index],
          'updatedAt': ++revision,
          if (method == 'setTaskPinned') 'pinned': input['pinned'],
          if (method == 'renameTask') 'title': input['title'],
          if (method == 'setTaskUnread') 'unreadAt': revision,
          if (method == 'archiveTask' || method == 'unarchiveTask') ...{
            'archived': method == 'archiveTask',
            'pinned': false
          }
        };
      }
      return {};
    };
    final store = DeviceStore(requireEncryption: false);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-sidebar&hash=synthetic&t=1',
        label: '合成测试设备');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => _IndexDevice(d.params!, bridge, initial));
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    await monitor.refreshTasks();
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: WorkspaceShell(
                device: device,
                workspace: workspace,
                monitor: monitor,
                sessions: sessions,
                preferences: prefs,
                sessionId: 'control',
                conversationBuilder: (_, id) =>
                    const Center(child: Text('当前正文保持不变'))))));
    await tester.pumpAndSettle();
    Future<void> openSidebar() async {
      if (find.byType(TaskNavigation).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('项目与任务').first);
        await tester.pumpAndSettle();
      }
    }

    Finder taskText(String text) => find.descendant(
        of: find.byType(TaskNavigation), matching: find.text(text));
    Future<void> menu(String title, String action) async {
      await openSidebar();
      await tester.ensureVisible(taskText(title));
      await tester.pumpAndSettle();
      final gesture =
          await tester.startGesture(tester.getCenter(taskText(title)));
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.up();
      await tester.pumpAndSettle();
      if (find.text(action).evaluate().isEmpty) {
        debugPrint(
            'QA missing menu $action: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().toList()}');
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
                '${environment!['cacheDirectory']}/qa-sidebar-missing-menu.png')
            .writeAsBytes(data!.buffer
                .asUint8List(data.offsetInBytes, data.lengthInBytes));
        image.dispose();
      }
      await tester.tap(find.text(action).last);
      if (action == '重命名任务') {
        // Native focused text keeps scheduling caret frames.
        await tester.pump(const Duration(milliseconds: 400));
      } else {
        await tester.pumpAndSettle();
      }
    }

    Future<void> capture(String name) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${environment!['cacheDirectory']}/qa-sidebar-$name.png')
          .writeAsBytes(
              data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      image.dispose();
    }

    await openSidebar();
    await capture('initial');
    await menu('测试任务', '置顶任务');
    expect(monitor.catalog.isPinned('target'), isTrue);
    expect(taskText('测试任务'), findsOneWidget);
    expect(find.text('已置顶'), findsOneWidget);
    await capture('pinned');
    await menu('测试任务', '取消置顶');
    expect(monitor.catalog.isPinned('target'), isFalse);
    await menu('测试任务', '重命名任务');
    await tester.enterText(find.byType(TextField).last, '  修改后的任务  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(taskText('修改后的任务'), findsOneWidget);
    await menu('修改后的任务', '标记为未读');
    expect(
        monitor.catalog.visible
            .firstWhere((t) => t.sessionId == 'target')
            .raw['unreadAt'],
        isNotNull);
    await menu('修改后的任务', '归档任务');
    expect(server.firstWhere((t) => t['taskId'] == 'target')['archived'],
        isNot(true));
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(monitor.catalog.isArchived('target'), isTrue);
    await tester.tap(find.byTooltip('归档'));
    await tester.pumpAndSettle();
    await capture('archived');
    await menu('修改后的任务', '取消归档任务');
    expect(monitor.catalog.isArchived('target'), isFalse);
    await tester.tap(find.byTooltip('关闭归档'));
    await tester.pumpAndSettle();
    rejectPin = true;
    await menu('修改后的任务', '置顶任务');
    expect(monitor.catalog.isPinned('target'), isFalse);
    expect(find.text('任务操作失败，请重试'), findsOneWidget);
    await capture('failure');
    rejectPin = false;
    await menu('修改后的任务', '归档任务');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('归档'));
    await tester.pumpAndSettle();
    await menu('修改后的任务', '删除任务');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(server.any((t) => t['taskId'] == 'target'), isTrue);
    await menu('修改后的任务', '删除任务');
    await tester.tap(find.text('删除任务').last);
    await tester.pumpAndSettle();
    expect(server.map((t) => t['taskId']), ['control']);
    final writes = bridge.channels.calls
        .where((c) => !c.method.startsWith('list'))
        .toList();
    expect(
        writes.every((c) =>
            (c.args.single as Map)['taskId'] == 'target' &&
            (c.args.single as Map)['workspaceIdentity'] == 'workspace'),
        isTrue);
    expect(writes.where((c) => c.method == 'deleteTask').length, 1);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(tester.takeException(), isNull);
    await capture('deleted');
    await tester.tap(find.byTooltip('关闭归档'));
    await tester.pumpAndSettle();
    await openSidebar();
    await prefs.setLanguage('en');
    await prefs.setTheme(ThemeMode.dark);
    await prefs.setTextScale(1.4);
    await tester.pumpAndSettle();
    await tester.longPress(taskText('原始任务'));
    await tester.pumpAndSettle();
    final pin = find.text('Pin task');
    expect(pin, findsOneWidget);
    final viewport = MediaQuery.sizeOf(tester.element(pin));
    for (final item in [
      'Pin task',
      'Rename task',
      'Archive task',
      'Mark as unread'
    ]) {
      final rect = tester.getRect(find.text(item));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
    }
    await capture('dark-large-menu');
    await tester.tapAt(Offset(viewport.width - 8, viewport.height / 2));
    await tester.pumpAndSettle();
    expect(find.text('Pin task'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    sessions.dispose();
    prefs.dispose();
    bridge.channels.dispose();
    debugPrint(
        'QA sidebar: pin/unpin, rename, unread, archive/restore, failure and delete confirmation passed; synthetic transport only.');
  });
}
