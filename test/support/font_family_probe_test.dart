import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
      .load();
}

void main() {
  testWidgets('probe test font override and material style inheritance',
      (tester) async {
    final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    if (captureDir != null && captureDir.isNotEmpty) {
      await tester.runAsync(() async {
        await _load('ProbeReviewUi', 'C:/Windows/Fonts/msyh.ttc');
        try {
          await _load('FlutterTest', 'C:/Windows/Fonts/msyh.ttc');
          debugPrint('font_probe FlutterTest load=success');
        } catch (error) {
          debugPrint('font_probe FlutterTest load=error $error');
        }
        try {
          await _load('Ahem', 'C:/Windows/Fonts/msyh.ttc');
          debugPrint('font_probe Ahem load=success');
        } catch (error) {
          debugPrint('font_probe Ahem load=error $error');
        }
      });
    }

    tester.view.physicalSize = const Size(860, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          final base = Theme.of(context);
          return Theme(
            data: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'ProbeReviewUi'),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'ProbeReviewUi'),
              child: RepaintBoundary(
                key: const ValueKey('font-probe-boundary'),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Inherited text: 中文按钮'),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Button child: 中文按钮'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 14),
                          ),
                          onPressed: () {},
                          child: const Text('Widget style: 中文按钮'),
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String>(
                          value: '中文按钮',
                          style: const TextStyle(fontSize: 14),
                          items: const [
                            DropdownMenuItem(
                              value: '中文按钮',
                              child: Text('Dropdown item: 中文按钮'),
                            ),
                          ],
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: 8),
                        Text('Explicit FlutterTest: 中文按钮',
                            style: const TextStyle(fontFamily: 'FlutterTest')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (captureDir != null && captureDir.isNotEmpty) {
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('font-probe-boundary')),
      );
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(captureDir).create(recursive: true);
          await File('$captureDir/font-family-probe.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  });
}
