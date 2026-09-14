import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/protocol/usage_statistics.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'package:zcode_remote/ui/usage/usage_charts.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';
import 'review_capture.dart';
import 'usage_fixtures.dart';

FeatureBridge _usageBridge(
    {required String planName, Completer<void>? usageGate}) {
  final bridge = FeatureBridge();
  bridge.channels.handler = (channel, method, args) async {
    if (method == 'get') {
      return {
        'modelProviderFamilyModes': {'bigmodel': 'oauth'},
        'modelProviderFamilySelectedKeys': {
          'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan'
        }
      };
    }
    if (method == 'getCodingPlanResetStatus') {
      return {
        'availableFiveHourResets': [],
        'availableWeekResets': [],
        'hasUnreadHistory': false
      };
    }
    if (usageGate != null &&
        (method == 'getCodingPlanUsageSnapshot' ||
            method == 'getAppUsageSnapshot')) {
      await usageGate.future;
    }
    final query = args.single as Map;
    return statisticsFixture(query['range'],
        application: method == 'getAppUsageSnapshot');
  };
  bridge.conversationTransport.quotaHandler =
      (providerId, organizationId, projectId) {
    final result = quotaFixture(providerId);
    result['subscription'] = {
      'details': [
        {'productName': planName}
      ]
    };
    return Future.value(result);
  };
  return bridge;
}

FakeWorkspaceMonitor _usageMonitor(FeatureBridge bridge,
    FakeAppSessions sessions, String deviceId, String workspaceKey) {
  return FakeWorkspaceMonitor(
      bridge: bridge,
      scope: {
        'workspaceIdentity': workspaceKey,
        'workspacePath': 'D:/Synthetic/$workspaceKey',
      },
      notifications: sessions.notifications,
      source: WorkspaceTaskSource(
          deviceId: deviceId,
          deviceLabel: deviceId,
          workspaceKey: workspaceKey));
}

void main() {
  testWidgets('embedded usage settles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const platform = MethodChannel('zcode_remote/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform,
            (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null));
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store = DeviceStore(requireEncryption: false);
    await store.load();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'get') {
        return {
          'modelProviderFamilyModes': {'bigmodel': 'oauth'},
          'modelProviderFamilySelectedKeys': {
            'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan'
          }
        };
      }
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      if (method == 'getEntitlementSnapshot') {
        return {
          'providerId': 'builtin:bigmodel-coding-plan',
          'planName': 'GLM Coding Plan'
        };
      }
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot');
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'embed-test',
          'workspacePath': 'D:/Synthetic',
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
          deviceId: 'synthetic-device',
          deviceLabel: 'Synthetic device',
          workspaceKey: 'embed-test',
        ));
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'usage',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      expect(find.text('App usage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });

  testWidgets('embedded usage preserves tab, range and scroll on return',
      (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    SharedPreferences.setMockInitialValues({});
    const platform = MethodChannel('zcode_remote/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform,
            (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store = DeviceStore(requireEncryption: false);
    await store.load();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = _usageBridge(planName: 'Return plan');
    final monitor = _usageMonitor(bridge, sessions, 'return-device', 'return');
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'usage',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('App usage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Last 30 days'));
      await tester.pump();
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      final usageScroll = find.byKey(const ValueKey('usage-page-scroll'));
      final scrollable = find
          .descendant(of: usageScroll, matching: find.byType(Scrollable))
          .first;
      await tester.drag(scrollable, const Offset(0, -420));
      await tester.pump();
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(before, greaterThan(0));
      final tab = tester
          .widget<UsageSwitch<bool>>(find.byType(UsageSwitch<bool>).first);
      final range = tester.widget<UsageSwitch<UsageRange>>(
          find.byType(UsageSwitch<UsageRange>));
      expect(tab.value, isTrue);
      expect(range.value, UsageRange.month);

      await tester.ensureVisible(find.text('General'));
      await tester.pump();
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usage stats'));
      await tester.pump();
      await tester.tap(find.text('Usage stats'));
      await tester.pumpAndSettle();

      final returnedScroll = find.byKey(const ValueKey('usage-page-scroll'));
      final returnedScrollable = find
          .descendant(of: returnedScroll, matching: find.byType(Scrollable))
          .first;
      final after =
          tester.state<ScrollableState>(returnedScrollable).position.pixels;
      expect(after, closeTo(before, 0.1));
      expect(
          tester
              .widget<UsageSwitch<bool>>(find.byType(UsageSwitch<bool>).first)
              .value,
          isTrue);
      expect(
          tester
              .widget<UsageSwitch<UsageRange>>(
                  find.byType(UsageSwitch<UsageRange>))
              .value,
          UsageRange.month);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
    }
  });

  testWidgets('embedded usage isolates a late result after source switch',
      (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    SharedPreferences.setMockInitialValues({});
    const platform = MethodChannel('zcode_remote/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform,
            (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store = DeviceStore(requireEncryption: false);
    await store.load();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final gate = Completer<void>();
    final bridgeA = _usageBridge(planName: 'Source A', usageGate: gate);
    final monitorA =
        _usageMonitor(bridgeA, sessions, 'device-a', 'workspace-a');
    final bridgeB = _usageBridge(planName: 'Source B');
    final monitorB =
        _usageMonitor(bridgeB, sessions, 'device-b', 'workspace-b');
    // U17: the statistics page resolves its Coding Plan source from the
    // persisted candidates, so both fake transports advertise a connected
    // bigmodel coding-plan provider.
    for (final bridge in [bridgeA, bridgeB]) {
      bridge.conversationTransport.families['modelProviders'] = [
        {'id': 'builtin:bigmodel-coding-plan', 'hasApiKey': true}
      ];
    }
    sessions.composers
        .obtain(
            transport: bridgeA.conversation(monitorA.scope),
            deviceId: 'device-a',
            workspaceKey: 'workspace-a')
        .usage
        .selectProvider('builtin:bigmodel-coding-plan');
    sessions.composers
        .obtain(
            transport: bridgeB.conversation(monitorB.scope),
            deviceId: 'device-b',
            workspaceKey: 'workspace-b')
        .usage
        .selectProvider('builtin:bigmodel-coding-plan');
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitorA,
              initialSection: 'usage',
              onManageDevices: () {})));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitorB,
              initialSection: 'usage',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Source B'), findsOneWidget);
      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Source A'), findsNothing);
      expect(find.text('Source B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      monitorA.dispose();
      monitorB.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
    }
  });

  testWidgets('device workspace return keeps the settings route',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=settings-device&hash=synthetic&t=1',
        label: 'Settings device');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    late BuildContext root;
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: Builder(builder: (context) {
            root = context;
            return const Scaffold(body: Text('Launcher'));
          })));
      await openDeviceWorkspace(root, sessions, preferences, device);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceShell), findsOneWidget);

      showSettingsCenter(
          tester.element(find.byType(WorkspaceShell)), sessions, preferences);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Devices'));
      await tester.pump();
      await tester.tap(find.text('Devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings device'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceShell, skipOffstage: false), findsNWidgets(2));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsCenterPage), findsOneWidget);
      expect(find.text('Your devices'), findsOneWidget);
      expect(find.text('Settings device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });

  testWidgets('capture U13 representative settings surfaces', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    const platform = MethodChannel('zcode_remote/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform,
            (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false);
    await store.load();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = _usageBridge(planName: 'Capture plan');
    final monitor =
        _usageMonitor(bridge, sessions, 'capture-device', 'capture');
    final wideKey = GlobalKey();
    final narrowKey = GlobalKey();
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      tester.view.physicalSize = const Size(1180, 900);
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: RepaintBoundary(
              key: wideKey,
              child: SettingsCenterPage(
                  preferences: preferences,
                  sessions: sessions,
                  remoteMonitor: monitor,
                  initialSection: 'usage',
                  onManageDevices: () {}))));
      await tester.pumpAndSettle();
      await captureReviewBoundary(
          tester, wideKey, 'u13-settings-zh-1180-usage');

      await preferences.setLanguage('en');
      await preferences.setTextScale(1.4);
      tester.view.physicalSize = const Size(344, 900);
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: RepaintBoundary(
              key: narrowKey,
              child: SettingsCenterPage(
                  preferences: preferences,
                  sessions: sessions,
                  remoteMonitor: monitor,
                  initialSection: 'devices',
                  onManageDevices: () {}))));
      await tester.pumpAndSettle();
      await captureReviewBoundary(
          tester, narrowKey, 'u13-settings-en-344-scale140-devices');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
    }
  });
}
