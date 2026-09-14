import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/official_icons.dart';

void main() {
  testWidgets('review: settings action icons paint visible pixels',
      (tester) async {
    for (final name in const [
      'pencil',
      'cpu',
      'box',
      'download',
      'plug',
      'chevron-left',
      'settings-2',
      'graduation-cap',
      'database',
      'bar-chart-3',
      'message',
      'history',
      'layers-2',
      'eye',
      'eye-off',
      'undo-2',
      'server',
      'anchor',
    ]) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: 32,
              child: LucideIcon(name, size: 32, color: Colors.black),
            ),
          ),
        ),
      ));
      await tester.pump();
      final visiblePixels = await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          var count = 0;
          for (var index = 3; index < bytes.length; index += 4) {
            if (bytes[index] > 0) count++;
          }
          return count;
        } finally {
          image.dispose();
        }
      });
      expect(visiblePixels, greaterThan(0),
          reason: '$name must not be an invisible action target.');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
