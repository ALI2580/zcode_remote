import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/mobile/option_sheet.dart';
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

  testWidgets(
      'compact model chip opens the bottom sheet and selection reaches config',
      (tester) async {
    await pumpToolbar(tester, 360);

    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsOneWidget);
    // The fixture models are all visible in the sheet.
    expect(find.text('GLM-5.2'), findsOneWidget);
    expect(find.text('Second model'), findsOneWidget);
    // Provider groups surface as section headings.
    expect(find.text('Provider B'), findsWidgets);

    // Search narrows the rows inside the sheet.
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pumpAndSettle();
    expect(find.text('GLM-5.2'), findsNothing);
    expect(find.text('Second model'), findsOneWidget);

    // Picking a model writes through the shared controller: no second
    // business state. Read the value back from config.
    await tester.tap(find.text('Second model'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsNothing);
    // config stores the short model name (same contract as the
    // anchored menu, see composer_ui_test).
    expect(controller.config['model'], 'second-model');
  });

  testWidgets(
      'compact mode chip opens the bottom sheet and selection reaches config',
      (tester) async {
    await pumpToolbar(tester, 360);

    await tester.tap(find.byKey(const ValueKey('composer-mode')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsOneWidget);

    final modes = controller.options.modes;
    expect(modes, isNotEmpty);
    final target = modes.firstWhere((m) => m.value != controller.config['mode'],
        orElse: () => modes.first);

    await tester
        .tap(find.byKey(ValueKey('mobile-sheet-option-${target.value}')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsNothing);
    expect(controller.config['mode'], target.value);
  });

  testWidgets('wide container keeps the anchored popover, not the sheet',
      (tester) async {
    await pumpToolbar(tester, 1000);

    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsNothing);
    // The anchored popover still shows the model rows (the other match is
    // the chip label itself).
    expect(find.byKey(const ValueKey('composer-model-option-builtin:zai/GLM-5.2')),
        findsOneWidget);
  });
}
