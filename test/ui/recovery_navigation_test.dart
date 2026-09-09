import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/recovery_journal.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';

class _Storage implements RecoveryStorage {
  String? data;
  bool reject = false;
  @override
  Future<List<String>> readCandidates() async => [if (data != null) data!];
  @override
  Future<void> write(String value, String? previous) async {
    if (reject) throw StateError('storage unavailable');
    data = value;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'navigation waits for recovery and opens the saved task with its editor and panel',
      (tester) async {
    final devices =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await devices.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-nav&hash=synthetic&t=1');
    final target = TaskTarget(
        deviceId: device.id,
        workspaceKey: 'workspace',
        sessionId: 'saved-task',
        title: '恢复任务');
    final storage = _Storage()
      ..data = jsonEncode({
        'schemaVersion': 1,
        'locations': {device.id: target.toJson()},
        'composers': {
          'entries': {
            composerKey(device.id, 'workspace', 'saved-task'): {
              'input': {'text': '恢复后的草稿'}
            }
          }
        },
        'panels': {
          target.key: {'panelOpen': true, 'panelTab': 'summary'}
        }
      });
    final bridge = FeatureBridge();
    final apps = FakeAppSessions(
        store: devices,
        recovery: RecoveryJournal(storage: storage, encrypted: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('设备入口'));
        })));
    await openDeviceWorkspace(root, apps, preferences, device);
    await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceShell>(find.byType(WorkspaceShell)).sessionId,
        'saved-task');
    expect(find.text('恢复后的草稿'), findsOneWidget);
    expect(apps.workspaceViewStates[target.key]!.panelOpen, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(apps.workspaceViewStates[target.key]!.panelOpen, isFalse);
    expect(find.byType(WorkspaceShell), findsOneWidget);
    expect(find.text('恢复后的草稿'), findsOneWidget);
    expect(bridge.conversationTransport.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    apps.dispose();
    await apps.notifications.settled;
    preferences.dispose();
  });

  testWidgets('a local persistence failure is visible and retry does not send',
      (tester) async {
    final storage = _Storage(), bridge = FeatureBridge();
    final apps = FakeAppSessions(
        store:
            DeviceStore(requireEncryption: false, encrypt: (_) async => null),
        recovery: RecoveryJournal(storage: storage, encrypted: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    await apps.loadRecovery();
    final controller = apps.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await controller.loadOptions();
    await apps.flushRecovery();
    await tester.pumpWidget(const ZcodeRemoteApp(home: SizedBox()));
    await tester.pumpWidget(ZcodeRemoteApp(
        home: Scaffold(
            body: Column(children: [
      const Spacer(),
      ComposerBar(controller: controller)
    ]))));
    storage.reject = true;
    controller.input.text = 'keep this draft';
    await apps.flushRecovery().catchError((_) {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-save-error')), findsOneWidget);
    expect(find.text('keep this draft'), findsOneWidget);
    storage.reject = false;
    await tester.tap(find.byKey(const ValueKey('draft-save-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-save-error')), findsNothing);
    expect(bridge.conversationTransport.sent, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    apps.dispose();
    await apps.notifications.settled;
  });
}
