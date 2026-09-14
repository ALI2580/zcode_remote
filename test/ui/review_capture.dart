import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadReviewCaptureFonts() async {
  if (Platform.environment['ZCODE_UI_CAPTURE_DIR'] == null) return;
  for (final font in {
    'Roboto': 'C:/Windows/Fonts/msyh.ttc',
    'monospace': 'C:/Windows/Fonts/consola.ttf',
    'MaterialIcons':
        'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final bytes = await File(font.value).readAsBytes();
    await (FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}

Future<void> captureReviewBoundary(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await captureReviewRenderBoundary(tester, render, name);
}

Future<void> captureReviewFinder(
    WidgetTester tester, Finder finder, String name) async {
  final render = tester.renderObject<RenderRepaintBoundary>(finder);
  await captureReviewRenderBoundary(tester, render, name);
}

Future<void> captureReviewRenderBoundary(
    WidgetTester tester, RenderRepaintBoundary render, String name) async {
  final directory = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  _repaint(render);
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Capture returned no PNG data');
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    debugDisableShadows = previousShadows;
    _repaint(render);
    await tester.pump();
  }
}

void _repaint(RenderObject render) {
  render.markNeedsPaint();
  render.visitChildren(_repaint);
}
