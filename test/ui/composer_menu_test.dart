import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_config.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/composer/composer_mode_metadata.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';
import 'fake_features.dart';
import 'review_capture.dart';

void main() {
  late FakeBridge bridge;
  late ComposerStore store;
  late ComposerController controller;

  setUpAll(loadReviewCaptureFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FakeBridge();
    store = ComposerStore();
    controller = store.obtain(
      transport: bridge.conversationTransport,
      deviceId: 'A',
      workspaceKey: 'workspace',
      sessionId: 'task',
    );
    final subscription = await bridge.conversationTransport.subscribe('task');
    controller.bind(subscription.state);
    await controller.loadOptions();
  });

  tearDown(() => store.dispose());

  Widget editor({
    double? composerWidth,
    VoidCallback? onManageModels,
    GlobalKey? reviewBoundaryKey,
  }) {
    final composer = Column(
      children: [
        const Spacer(),
        ComposerBar(controller: controller, onManageModels: onManageModels),
      ],
    );
    return MaterialApp(
      theme: ZInkTheme.light(),
      builder: (context, child) => RepaintBoundary(
        key: reviewBoundaryKey,
        child: child!,
      ),
      home: Scaffold(
        body: composerWidth == null
            ? composer
            : Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(width: composerWidth, child: composer),
              ),
      ),
    );
  }

  testWidgets('mode rows use official icons, labels, descriptions and order',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(editor(reviewBoundaryKey: boundary));
    await tester.tap(find.byKey(const ValueKey('composer-mode')));
    await tester.pumpAndSettle();

    final values = ['build', 'edit', 'plan', 'yolo'];
    for (final value in values) {
      expect(find.byKey(ValueKey('composer-mode-option-$value-icon')),
          findsOneWidget);
      expect(find.byKey(ValueKey('composer-mode-option-$value-description')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('composer-mode-option-build')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mode-option-build-label')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mode-option-build-icon')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mode-option-build')),
        findsOneWidget);
    expect(
        tester.getTopLeft(
            find.byKey(const ValueKey('composer-mode-option-build'))),
        isNotNull);

    await captureReviewBoundary(tester, boundary, 'u09-mode-menu-viewport');
    await tester.tap(find.byKey(const ValueKey('composer-mode-option-plan')));
    await tester.pumpAndSettle();
    expect(controller.config['mode'], 'plan');
  });

  testWidgets('model menu groups by provider id and opens a model submenu',
      (tester) async {
    await tester.pumpWidget(editor());
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('composer-model-provider-builtin:zai')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('composer-model-provider-provider-b')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('composer-model-provider-provider-b')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey(
            'composer-model-option-custom:provider-b:second-model')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(
        'composer-model-option-custom:provider-b:second-model')));
    await tester.pumpAndSettle();
    expect(controller.config['provider'], 'provider-b');
    expect(controller.config['model'], 'second-model');
    expect(controller.config['thought'], 'enabled');
  });

  testWidgets('mode translations stay scoped to the provider family',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Column(
          children: [
            Text(modeLabel(context, 'auto', 'server auto', 'claude')),
            Text(modeLabel(context, 'build', 'server build', 'opencode')),
            Text(modeLabel(context, 'full-access', 'server full', 'codex')),
            Text(modeDescription(context,
                    ConfigOptionValue.fromRaw({'value': 'auto'}), 'claude') ??
                ''),
          ],
        ),
      ),
    ));
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Full access'), findsOneWidget);
    expect(find.text('Choose permissions automatically.'), findsOneWidget);
    expect(find.text('自动编辑'), findsNothing);
  });

  testWidgets('manage models footer invokes the current composer callback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(editor(onManageModels: () => calls++));
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('composer-manage-models')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('composer-manage-models')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('provider submenu prefers the right side and remains in bounds',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester
        .pumpWidget(editor(composerWidth: 700, reviewBoundaryKey: boundary));
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    final provider =
        find.byKey(const ValueKey('composer-model-provider-provider-b'));
    final providerRect = tester.getRect(provider);
    await tester.tap(provider);
    await tester.pumpAndSettle();
    final popovers = find.byKey(const ValueKey('composer-popover'));
    final submenuRect = tester.getRect(popovers.last);
    expect(submenuRect.left, greaterThanOrEqualTo(providerRect.right));
    expect(submenuRect.left - providerRect.right, closeTo(4, .1));
    expect(submenuRect.right, lessThanOrEqualTo(984));
    expect(submenuRect.bottom, lessThanOrEqualTo(692));
    await captureReviewBoundary(
        tester, boundary, 'u09-u10-provider-submenu-wide-viewport');
  });

  testWidgets('narrow provider submenu clamps and Escape returns to parent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 600);
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(editor(reviewBoundaryKey: boundary));
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('composer-model-provider-provider-b')));
    await tester.pumpAndSettle();
    final popovers = find.byKey(const ValueKey('composer-popover'));
    final submenuRect = tester.getRect(popovers.last);
    expect(submenuRect.left, greaterThanOrEqualTo(16));
    expect(submenuRect.right, lessThanOrEqualTo(284));
    expect(submenuRect.top, greaterThanOrEqualTo(8));
    expect(submenuRect.bottom, lessThanOrEqualTo(592));
    await captureReviewBoundary(
        tester, boundary, 'u09-u10-provider-submenu-narrow-viewport');
    expect(
        find.byKey(const ValueKey(
            'composer-model-option-custom:provider-b:second-model')),
        findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-model-provider-provider-b')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey(
            'composer-model-option-custom:provider-b:second-model')),
        findsNothing);
  });

  testWidgets('model metadata decorates provider and vision-capable rows',
      (tester) async {
    final metadataBridge = FeatureBridge();
    metadataBridge.channels.handler = (channel, method, args) async {
      if (channel == Channels.modelProvider && method == 'getAll') {
        return [
          {
            'id': 'provider-b',
            'name': 'Provider B',
            'source': 'custom',
            'badgeLabel': 'API',
            'models': [
              {
                'id': 'second-model',
                'name': 'Second model',
                'modalities': {
                  'input': ['text', 'image'],
                  'output': ['text'],
                },
              },
            ],
          },
        ];
      }
      if (channel == Channels.modelProvider && method == 'getDisplayOrder') {
        return ['provider-b'];
      }
      return {};
    };
    final metadataStore = ComposerStore();
    addTearDown(metadataStore.dispose);
    final metadataController = metadataStore.obtain(
      transport: metadataBridge.conversationTransport,
      deviceId: 'A',
      workspaceKey: 'workspace',
      sessionId: 'task',
    );
    final subscription =
        await metadataBridge.conversationTransport.subscribe('task');
    metadataController.bind(subscription.state);
    await metadataController.loadOptions();

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            ComposerBar(controller: metadataController),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('composer-model-badge-API')), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('composer-model-provider-provider-b')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey(
            'composer-model-option-custom:provider-b:second-model-vision')),
        findsOneWidget);
  });

  test('start-plan recommendation order follows the official pinned set', () {
    final options = ComposerOptions(WorkspacePrep.fromRaw({
      'configOptions': [
        {
          'id': 'model',
          'category': 'model',
          'type': 'select',
          'options': [
            {
              'value': 'builtin:zai-start-plan/other',
              'name': 'Other',
              'modelProviderId': 'builtin:zai-start-plan',
            },
            {
              'value': 'builtin:zai-start-plan/GLM-5-Turbo',
              'name': 'GLM-5-Turbo',
              'modelProviderId': 'builtin:zai-start-plan',
            },
            {
              'value': 'builtin:zai-start-plan/GLM-5.2',
              'name': 'GLM-5.2',
              'modelProviderId': 'builtin:zai-start-plan',
            },
          ],
        },
      ],
    }));

    expect(options.models.map((option) => option.name),
        ['GLM-5.2', 'GLM-5-Turbo', 'Other']);
  });

  testWidgets('mode family resolves from the exposed mode set (U18)',
      (tester) async {
    // The official glm vocabulary is unique to the glm family.
    expect(familyForModeValues(['default', 'build', 'edit', 'plan', 'yolo']),
        'glm');
    // Claude's acceptEdits/dontAsk/bypassPermissions identify claude.
    expect(familyForModeValues(['default', 'plan', 'acceptEdits']), 'claude');
    expect(familyForModeValues(['read-only', 'agent', 'full-access']), 'codex');
    // A bare plan is ambiguous: no family may claim the label.
    expect(familyForModeValues(['plan']), isNull);
    expect(familyForModeValues(const <String>[]), isNull);
    // Unknown values keep the server label in either language.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Column(children: [
          Text(modeLabel(context, 'plan', 'Plan',
              'custom:my-provider', 'glm')),
          Text(modeLabel(context, 'customMode', 'Server label',
              'custom:my-provider', null)),
        ]),
      ),
    ));
    await tester.pump();
    expect(find.text('Plan mode'), findsOneWidget);
    expect(find.text('Server label'), findsOneWidget);
  });
}
