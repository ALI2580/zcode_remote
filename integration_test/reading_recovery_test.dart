import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/recovery_journal.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import '../test/ui/fake_history.dart';
import '../test/ui/fake_workspace.dart';

const phase = String.fromEnvironment('READING_QA_PHASE', defaultValue: 'seed');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native paged reading recovery ($phase)', (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    final prefs = await SharedPreferences.getInstance();
    if (phase == 'seed') {
      await prefs.remove(PreferencesRecoveryStorage.key);
      await prefs.remove(PreferencesRecoveryStorage.backupKey);
    }
    final bridge = FakeBridge();
    bridge.conversationTransport.states['reading'] =
        readingState(phase == 'seed' ? 1 : 801, 860);
    bridge.conversationTransport.historyHandler =
        (_, before, __) async => readingPage(before!);
    final apps = FakeAppSessions(
      store: DeviceStore(requireEncryption: false, encrypt: (_) async => null),
      recovery: RecoveryJournal.production(),
      sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
    );
    await apps.loadRecovery();
    final key = composerKey('A', 'work', 'reading');
    if (phase == 'seed') {
      apps.conversationViewStates[key] = ConversationViewState()
        ..following = false
        ..anchor = '450'
        ..anchorOffset = -19
        ..logEpoch = 'reading-fixture';
    }
    final view = apps.conversationViewStates[key]!;
    final expectedAnchor = view.anchor!, expectedOffset = view.anchorOffset;
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
          home: ChatPage(
              session: bridge,
              scope: const {},
              workspaceKey: 'work',
              deviceId: 'A',
              sessionId: 'reading',
              title: '阅读恢复 QA · $phase',
              composerStore: apps.composers,
              viewStates: apps.conversationViewStates),
        )));
    await tester.pumpAndSettle();
    if (phase == 'seed') {
      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      final beforeDrag = list.controller!.offset;
      await tester.drag(find.byType(SuperListView), const Offset(0, -85));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(beforeDrag + 40));
      expect(view.following, isFalse);
      expect(int.parse(view.anchor!), lessThan(801));
      await apps.flushRecovery();
      expect(
          prefs.getString(PreferencesRecoveryStorage.key), startsWith('enc:'));
    } else {
      expect(
          bridge.conversationTransport.historyRequests
              .map((r) => r.beforeRowId),
          [801, 601]);
      expect(view.anchor, expectedAnchor);
      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      final viewport = tester
          .widget<ConversationViewport>(find.byType(ConversationViewport));
      final index = viewport.ids.indexOf(expectedAnchor) + 1;
      expect(index, greaterThan(0));
      expect(
          list.listController!.getOffsetToReveal(index, 0) -
              list.controller!.offset,
          closeTo(expectedOffset, 1));
      expect(view.following, isFalse);
    }
    expect(bridge.conversationTransport.commands, isEmpty);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final captured = await render.toImage(pixelRatio: 1);
    final bytes = await captured.toByteData(format: ui.ImageByteFormat.png);
    await File('${environment!['cacheDirectory']}/qa-reading-$phase.png')
        .writeAsBytes(bytes!.buffer
            .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    captured.dispose();
    debugPrint(
        'QA reading $phase: saved row ${view.anchor}, offset ${view.anchorOffset}; '
        '${bridge.conversationTransport.historyRequests.length} pages; no commands.');
    await tester.pumpWidget(const SizedBox.shrink());
    apps.dispose();
    await apps.notifications.settled;
  });
}
