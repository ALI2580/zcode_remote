import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_captcha.dart';

class _DeferredChallenge extends ModelCaptchaChallengeAdapter {
  final result = Completer<String?>();
  final started = <String>[];
  final cancelled = <String>[];
  @override
  Future<String?> verify(ModelCaptchaChallengeRequest request) {
    started.add(request.requestId);
    return result.future;
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelled.add(requestId);
  }
}

void main() {
  test(
      'review: cancelling an old CAPTCHA frees the next scope before a late SDK response',
      () async {
    final oldAdapter = _DeferredChallenge();
    final nextAdapter = _DeferredChallenge();
    ModelCaptchaService service(ModelCaptchaChallengeAdapter adapter) =>
        ModelCaptchaService(
            configLoader: () => {
                  'enabled': true,
                  'region': 'cn',
                  'prefix': 'synthetic',
                  'sceneId': 'review'
                },
            challengeAdapter: adapter);
    final oldService = service(oldAdapter);
    final nextService = service(nextAdapter);
    Object? oldError;
    final oldResult = oldService
        .resolveHeaders(providerId: 'old', requestId: 'old-request')
        .catchError((Object e) {
      oldError = e;
      return <String, dynamic>{};
    });
    Future<Map<String, dynamic>>? nextResult;
    try {
      await pumpEventQueue();
      expect(oldAdapter.started, ['old-request']);
      await oldService.cancel('old-request');
      nextResult = nextService.resolveHeaders(
          providerId: 'next', requestId: 'next-request');
      await pumpEventQueue();
      expect(nextAdapter.started, ['next-request'],
          reason:
              'A cancelled scope must release the shared queue even when native success arrives late.');
      expect(oldError, isA<ModelCaptchaException>());
      expect(oldAdapter.cancelled, ['old-request']);
      nextAdapter.result.complete('new-verification-param');
      expect((await nextResult)['X-Aliyun-Captcha-Verify-Param'],
          'new-verification-param');
    } finally {
      if (!oldAdapter.result.isCompleted) {
        oldAdapter.result.complete('late-old-param');
      }
      if (!nextAdapter.result.isCompleted) {
        nextAdapter.result.complete('new-verification-param');
      }
      await oldResult;
      await nextResult;
      oldService.dispose();
      nextService.dispose();
    }
  });
}
