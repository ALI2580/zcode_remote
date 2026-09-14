import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/ui/model_connectivity_button.dart';
import 'package:zcode_remote/ui/official_icons.dart';

void main() {
  testWidgets('has official tooltip and invokes the model callback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ModelConnectivityButton(
        modelId: 'model-a',
        hasApiKey: true,
        onTest: () async => calls++,
      ),
    ));

    // Official affordance (js-1 model row): ghost button with the `unplug`
    // glyph titled 测试模型/Test model.
    expect(find.byTooltip('Test model'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is LucideIcon && widget.name == 'unplug'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Test model'));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('disables empty model, missing key, and pending attempts',
      (tester) async {
    final callback = Completer<void>();
    Future<void> onTest() => callback.future;
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          ModelConnectivityButton(modelId: '', hasApiKey: true, onTest: onTest),
          ModelConnectivityButton(
              modelId: 'model-a', hasApiKey: false, onTest: onTest),
          const ModelConnectivityButton(
              modelId: 'model-a', hasApiKey: true, pending: true),
        ],
      ),
    ));

    final buttons = find.byType(IconButton);
    expect(buttons, findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      final button = tester.widget<IconButton>(buttons.at(index));
      expect(button.onPressed, isNull);
    }
    callback.complete();
  });

  testWidgets('pending swaps to a spinner and never exposes request data',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModelConnectivityButton(
        modelId: 'model-a',
        hasApiKey: true,
        pending: true,
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is LucideIcon && widget.name == 'unplug'),
        findsNothing);
    expect(find.textContaining('apiKey'), findsNothing);
  });

  testWidgets('renders the official result pill below the row',
      (tester) async {
    const failure = ModelConnectivityOutcome(
      success: false,
      failureReason: 'timeout from endpoint',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Column(
        children: [
          ModelConnectivityResultPill(
              outcome: ModelConnectivityOutcome(success: true)),
          ModelConnectivityResultPill(outcome: failure),
          ModelConnectivityResultPill(
            outcome: ModelConnectivityOutcome(
              success: false,
              noEndpointResult: true,
            ),
          ),
        ],
      ),
    ));
    expect(find.text('Connected!'), findsOneWidget);
    expect(find.text('Connection failed: timeout from endpoint'),
        findsOneWidget);
    expect(find.text('No endpoint configured'), findsOneWidget);
    expect(find.textContaining('apiKey'), findsNothing);
  });
}
