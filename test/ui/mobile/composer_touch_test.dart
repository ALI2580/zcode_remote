import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/theme.dart';
import '../fake_workspace.dart';

void main() {
  late FakeBridge bridge;
  late ComposerStore store;
  late ComposerController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FakeBridge();
    store = ComposerStore();
    controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: 'task');
    final subscription = await bridge.conversationTransport.subscribe('task');
    controller.bind(subscription.state);
    await controller.loadOptions();
  });
  tearDown(() {
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpToolbar(WidgetTester tester, double containerWidth) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: containerWidth,
                    child: ComposerToolbar(
                        controller: controller, onSend: () {}))))));
    await tester.pumpAndSettle();
  }

  testWidgets('compact container gives submit and chips 48px rows',
      (tester) async {
    await pumpToolbar(tester, 360);
    expect(tester.takeException(), isNull);

    final submit = tester.getRect(find.byKey(const ValueKey('composer-submit')));
    expect(submit.width, greaterThanOrEqualTo(48));
    expect(submit.height, greaterThanOrEqualTo(48));

    for (final id in ['composer-mode', 'composer-model']) {
      final chip = tester.getRect(find.byKey(ValueKey(id)));
      expect(chip.height, greaterThanOrEqualTo(48), reason: id);
    }

    // Primary action must not overlap any chip.
    for (final id in ['composer-mode', 'composer-model']) {
      final chip = tester.getRect(find.byKey(ValueKey(id)));
      expect(submit.intersect(chip).isEmpty, isTrue,
          reason: 'submit must not overlap $id');
    }
  });

  testWidgets('wide container keeps the official desktop sizes',
      (tester) async {
    await pumpToolbar(tester, 1000);
    expect(tester.takeException(), isNull);

    final submit = tester.getRect(find.byKey(const ValueKey('composer-submit')));
    expect(submit.width, closeTo(28, 0.1));
    expect(submit.height, closeTo(28, 0.1));
    final chip = tester.getRect(find.byKey(const ValueKey('composer-model')));
    expect(chip.height, closeTo(28, 0.1));
  });
}
