import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_captcha.dart';

class _UnusedChallenge extends ModelCaptchaChallengeAdapter {
  @override
  Future<String?> verify(ModelCaptchaChallengeRequest request) async =>
      throw StateError('Only configuration retry is under review');
  @override
  Future<void> cancel(String requestId) async {}
}

void main() {
  test(
      'review: transient CAPTCHA config RPC failure does not suppress the next retry for sixty seconds',
      () async {
    var reads = 0;
    final service = ModelCaptchaService(
        configLoader: () async {
          reads++;
          if (reads == 1) {
            throw StateError('synthetic temporary transport failure');
          }
          return {
            'enabled': true,
            'region': 'cn',
            'prefix': 'review',
            'sceneId': 'review'
          };
        },
        challengeAdapter: _UnusedChallenge());
    addTearDown(service.dispose);
    expect(await service.getCaptchaConfig(), isNull);
    expect((await service.getCaptchaConfig())?.usable, isTrue,
        reason:
            'The official zQ cache is written only when getCaptchaConfig completes successfully.');
    expect(reads, 2);
    expect((await service.getCaptchaConfig())?.usable, isTrue);
    expect(reads, 2, reason: 'A successful configuration is still cached.');
  });

  test(
      'review: invalidateConfig prevents an old in-flight success from refilling cache',
      () async {
    var reads = 0;
    final oldResponse = Future<Object?>.value({
      'enabled': true,
      'region': 'old-region',
      'prefix': 'old-prefix',
      'sceneId': 'old-scene',
    });
    final service = ModelCaptchaService(
      configLoader: () async {
        reads++;
        if (reads == 1) {
          return oldResponse;
        }
        return {
          'enabled': true,
          'region': 'new-region',
          'prefix': 'new-prefix',
          'sceneId': 'new-scene',
        };
      },
      challengeAdapter: _UnusedChallenge(),
    );
    addTearDown(service.dispose);

    final old = service.getCaptchaConfig();
    service.invalidateConfig();
    expect((await old)?.region, 'old-region');
    expect((await service.getCaptchaConfig())?.region, 'new-region');
    expect(reads, 2);
  });
}
