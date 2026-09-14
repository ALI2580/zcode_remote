import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ui/search_snippet_priority_acceptance_review_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native old snippet is visible with real device typography',
      (tester) async {
    if (!const bool.fromEnvironment('NATIVE_SEARCH_VISUAL_REVIEW')) return;
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    const runId = String.fromEnvironment('NATIVE_SEARCH_VISUAL_RUN_ID');
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(runId), isTrue);
    final directory = Directory(
        '${environment!['cacheDirectory']}/native-search-visual/$runId');
    expect(await directory.exists(), isFalse);
    await directory.create(recursive: true);
    final key = GlobalKey();
    await runSearchSnippetPriorityReview(tester, captureKey: key,
        onVisible: () async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/selected-snippet.png')
            .writeAsBytes(data!.buffer.asUint8List());
        await File('${directory.path}/manifest.json').writeAsString(jsonEncode({
          'runId': runId,
          'source': 'synthetic FakeBridge; no network or remote writes',
          'surface': 'real ChatPage with native typography and device viewport',
          'width': image.width,
          'height': image.height,
          'assertions': 'selected snippet beats 20 newer query matches; older '
              'page loaded; target and highlight inside viewport',
          'officialSameData': false,
        }));
      } finally {
        image.dispose();
      }
    });
  });
}
