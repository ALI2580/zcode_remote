import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zcode_remote/update/update_downloader.dart';

void main() {
  group('UpdateDownloader', () {
    test('parses MD5 hex from content', () {
      expect(
          UpdateDownloader.parseMd5Hex(
              'abc123 d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9'),
          'd4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9');
      expect(UpdateDownloader.parseMd5Hex('no hash here'), isNull);
    });

    test('idle -> downloading -> done with valid content', () async {
      final states = <DownloadState>[];
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            List.generate(100, (i) => i % 256),
          ]),
          200,
          contentLength: 100,
        );
      });
      final downloader = UpdateDownloader(client: client);
      downloader.addListener(() => states.add(downloader.progress.state));

      final result =
          await downloader.download(url: 'https://example.com/test.apk');
      expect(result, isNotNull, reason: 'download should succeed');
      expect(downloader.progress.state, DownloadState.done);
      downloader.dispose();
    });

    test('fails with HTTP error status', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.fromIterable([Uint8List(0)]), 404);
      });
      final downloader = UpdateDownloader(client: client);
      final result = await downloader.download(
          url: 'https://example.com/test.apk', maxRetries: 0);
      expect(result, isNull);
      expect(downloader.progress.state, DownloadState.failed);
      downloader.dispose();
    });
  });

  test('cancel transitions from downloading to cancelled', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      // Return a large stream that never completes to simulate slow download
      final controller = StreamController<List<int>>();
      controller.add(List.generate(50, (i) => i % 256));
      return http.StreamedResponse(
        controller.stream,
        200,
        contentLength: 10000,
      );
    });
    final downloader = UpdateDownloader(client: client);
    // Start download (don't await)
    final downloadFuture =
        downloader.download(url: 'https://example.com/slow.apk', maxRetries: 0);
    // Wait a bit then cancel
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await downloader.cancel();
    expect(downloader.progress.state, DownloadState.cancelled);
    final result = await downloadFuture;
    expect(result, isNull, reason: 'cancelled download returns null');
    downloader.dispose();
  });

  test('retry after failure attempts again', () async {
    var attempts = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      attempts++;
      if (attempts <= 1) {
        return http.StreamedResponse(Stream.fromIterable([]), 500);
      }
      return http.StreamedResponse(
        Stream.fromIterable([List.generate(10, (i) => i % 256)]),
        200,
        contentLength: 10,
      );
    });
    final downloader = UpdateDownloader(client: client);
    final result = await downloader.download(
        url: 'https://example.com/retry.apk', maxRetries: 2);
    expect(attempts, greaterThanOrEqualTo(2),
        reason: 'should retry after first failure');
    expect(result, isNotNull, reason: 'second attempt should succeed');
    downloader.dispose();
  });
}
