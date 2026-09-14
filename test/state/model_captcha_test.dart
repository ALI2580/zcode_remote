import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/model_captcha.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';

import '../ui/fake_features.dart';

class _FakeCaptchaAdapter extends ModelCaptchaChallengeAdapter {
  final values = <String>[];
  final requests = <ModelCaptchaChallengeRequest>[];
  final cancelled = <String>[];
  final started = <String>[];
  Completer<void>? gate;
  bool completeGateOnCancel = true;

  @override
  Future<String?> verify(ModelCaptchaChallengeRequest request) async {
    requests.add(request);
    started.add(request.requestId);
    final currentGate = gate;
    if (currentGate != null) await currentGate.future;
    return values.removeAt(0);
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelled.add(requestId);
    if (completeGateOnCancel) gate?.complete();
  }
}

ModelCaptchaConfig _config() => const ModelCaptchaConfig(
      enabled: true,
      region: 'cn',
      prefix: 'prefix',
      sceneId: 'scene',
    );

void main() {
  test('getCaptchaConfig uses no args, caches for 60 seconds, and deduplicates',
      () async {
    var reads = 0;
    var now = DateTime(2026, 9, 13);
    final adapter = _FakeCaptchaAdapter()..values.add('param-1');
    final service = ModelCaptchaService(
      configLoader: () async {
        reads++;
        return _config().safeMap;
      },
      challengeAdapter: adapter,
      clock: () => now,
    );
    addTearDown(service.dispose);

    final first = service.getCaptchaConfig();
    final duplicate = service.getCaptchaConfig();
    expect(identical(first, duplicate), isTrue);
    expect((await first)?.safeMap, _config().safeMap);
    expect(await service.getCaptchaConfig(), _config());
    expect(reads, 1);

    now = now.add(const Duration(seconds: 59));
    await service.getCaptchaConfig();
    expect(reads, 1);
    now = now.add(const Duration(seconds: 2));
    await service.getCaptchaConfig();
    expect(reads, 2);
  });

  test('builds exact one-time verification headers and rejects F008 reuse',
      () async {
    final adapter = _FakeCaptchaAdapter()..values.addAll(['fresh', 'fresh']);
    var language = 'en';
    final service = ModelCaptchaService(
      configLoader: () => _config().safeMap,
      challengeAdapter: adapter,
      languageProvider: () => language,
    );
    addTearDown(service.dispose);

    final first = service.resolveHeaders(providerId: 'provider-a');
    language = 'zh-CN';
    expect(
      await first,
      {
        'X-Aliyun-Captcha-Verify-Param': 'fresh',
        'X-Aliyun-Captcha-Verify-Region': 'cn',
      },
    );
    await expectLater(
      service.resolveHeaders(providerId: 'provider-a'),
      throwsA(isA<ModelCaptchaException>()
          .having((error) => error.code, 'code', 'captcha_duplicate')),
    );
    expect(adapter.requests.first.platformArguments.keys.toSet(), {
      'region',
      'prefix',
      'sceneId',
      'language',
      'requestId',
    });
    expect(adapter.requests.first.platformArguments['language'], 'cn');
  });

  test('missing, disabled, and incomplete config fail visibly without adapter',
      () async {
    for (final config in <Object?>[
      null,
      const {'enabled': false, 'region': 'cn', 'prefix': 'p', 'sceneId': 's'},
      const {'enabled': true, 'region': 'cn', 'prefix': '', 'sceneId': 's'},
    ]) {
      final adapter = _FakeCaptchaAdapter();
      final service = ModelCaptchaService(
        configLoader: () => config,
        challengeAdapter: adapter,
      );
      await expectLater(
        service.resolveHeaders(providerId: 'provider-a'),
        throwsA(isA<ModelCaptchaException>()),
      );
      expect(adapter.requests, isEmpty);
      service.dispose();
    }
  });

  test('serializes challenges globally and cancellation is scoped to itself',
      () async {
    final firstAdapter = _FakeCaptchaAdapter()
      ..values.add('first')
      ..gate = Completer<void>();
    final secondAdapter = _FakeCaptchaAdapter()..values.add('second');
    final first = ModelCaptchaService(
      configLoader: () => _config().safeMap,
      challengeAdapter: firstAdapter,
    );
    final second = ModelCaptchaService(
      configLoader: () => _config().safeMap,
      challengeAdapter: secondAdapter,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final old = first.resolveHeaders(
      providerId: 'old-provider',
      requestId: 'old-request',
    );
    await Future<void>.delayed(Duration.zero);
    final current = second.resolveHeaders(
      providerId: 'new-provider',
      requestId: 'new-request',
    );
    await Future<void>.delayed(Duration.zero);
    expect(firstAdapter.started, ['old-request']);
    expect(secondAdapter.started, isEmpty);

    await first.cancel('old-request');
    await expectLater(old, throwsA(isA<ModelCaptchaException>()));
    expect(firstAdapter.cancelled, ['old-request']);
    expect(await current, {
      'X-Aliyun-Captcha-Verify-Param': 'second',
      'X-Aliyun-Captcha-Verify-Region': 'cn',
    });
    expect(secondAdapter.started, ['new-request']);
  });

  test(
      'fromSession calls coding-plan config method with an empty argument list',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.codingPlanSubscription);
      expect(method, 'getCaptchaConfig');
      expect(args, isEmpty);
      return _config().safeMap;
    };
    final service = ModelCaptchaService.fromSession(
      session: bridge,
      challengeAdapter: _FakeCaptchaAdapter(),
    );
    addTearDown(service.dispose);
    expect(await service.getCaptchaConfig(), _config());
  });

  test(
      'plan gate uses captcha resolver and ordinary custom provider stays direct',
      () async {
    final bridge = FeatureBridge();
    var rpcCalls = 0;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'testModelConnectivity') {
        rpcCalls++;
        return {
          'results': [
            {'success': true}
          ],
        };
      }
      return <String, dynamic>{};
    };
    final adapter = _FakeCaptchaAdapter()..values.add('plan-param');
    final service = ModelCaptchaService(
      configLoader: () => _config().safeMap,
      challengeAdapter: adapter,
    );
    final controller = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
      dynamicHeadersResolver:
          createModelConnectivityDynamicHeadersResolver(captcha: service),
    );
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    final planRaw = <String, dynamic>{
      'id': 'plan',
      'name': 'Plan',
      'source': 'builtin',
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'endpoints': {'baseURL': 'https://synthetic.invalid/api/v1/zcode-plan'},
      'models': [
        {'id': 'model', 'name': 'Model'},
      ],
    };
    final customRaw = <String, dynamic>{
      ...planRaw,
      'id': 'custom',
      'endpoints': {'baseURL': 'https://synthetic.invalid/v1'},
      'apiKey': 'secret',
    };
    final plan = ModelProviderEntry.fromRaw(planRaw);
    final custom = ModelProviderEntry.fromRaw(customRaw);

    // A plan request with unavailable config must stop before test RPC.
    service.invalidateConfig();
    final failingService = ModelCaptchaService(
      configLoader: () => null,
      challengeAdapter: _FakeCaptchaAdapter(),
    );
    final failingController = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
      dynamicHeadersResolver: createModelConnectivityDynamicHeadersResolver(
        captcha: failingService,
      ),
    );
    expect(
        (await failingController.testModel(
                provider: plan, model: plan.models.single))
            .success,
        isFalse);
    expect(rpcCalls, 0);
    failingController.dispose();
    failingService.dispose();

    expect(
        (await controller.testModel(
                provider: custom, model: custom.models.single))
            .success,
        isTrue);
    expect(rpcCalls, 1);
    expect(adapter.requests, isEmpty);
    final standaloneResolver = createModelConnectivityDynamicHeadersResolver(
      captcha: service,
    );
    expect(await standaloneResolver(custom, custom.raw), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('withCaptcha invalidation cancels its own request before any test RPC',
      () async {
    final bridge = FeatureBridge();
    var rpcCalls = 0;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'testModelConnectivity') rpcCalls++;
      return {
        'results': [
          {'success': true}
        ],
      };
    };
    final adapter = _FakeCaptchaAdapter()
      ..gate = Completer<void>()
      ..values.add('will-not-be-sent');
    final service = ModelCaptchaService(
      configLoader: () => _config().safeMap,
      challengeAdapter: adapter,
    );
    final controller = ModelConnectivityController.withCaptcha(
      session: bridge,
      scopeKey: 'device|workspace',
      captcha: service,
    );
    addTearDown(controller.dispose);

    final provider = ModelProviderEntry.fromRaw({
      'id': 'plan',
      'name': 'Plan',
      'source': 'builtin',
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'endpoints': {'baseURL': 'https://synthetic.invalid/api/v1/zcode-plan'},
      'models': [
        {'id': 'model', 'name': 'Model'},
      ],
    });
    final pending = controller.testModel(
      provider: provider,
      model: provider.models.single,
    );
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, hasLength(1));
    controller.invalidateProvider('plan');
    final outcome = await pending;
    expect(outcome.success, isFalse);
    expect(adapter.cancelled, hasLength(1));
    expect(rpcCalls, 0);
  });
}
