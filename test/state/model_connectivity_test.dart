import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';

import '../ui/fake_features.dart';

Map<String, dynamic> _rawProvider({
  String id = 'custom-provider',
  String source = 'custom',
  String apiKey = 'confirmed-secret',
  String baseUrl = 'https://synthetic.invalid',
  bool includeApiKey = true,
  bool includeHeaders = true,
}) =>
    {
      'id': id,
      'name': 'Synthetic provider',
      'source': source,
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      if (includeApiKey) 'apiKey': apiKey,
      if (includeHeaders) 'headers': {'x-visible': 'confirmed-header'},
      'endpoints': {
        'baseURL': baseUrl,
        'paths': {'anthropic-messages': '/v1/messages'},
      },
      'modelSupportedFormats': ['text'],
      'models': [
        {
          'id': 'model-old',
          'name': 'Old label',
          'kinds': ['anthropic'],
          'defaultKind': 'anthropic',
          'contextWindow': 128000,
        }
      ],
    };

ModelProviderEntry _provider({
  String id = 'custom-provider',
  String source = 'custom',
  String apiKey = 'confirmed-secret',
  String baseUrl = 'https://synthetic.invalid',
  bool includeApiKey = true,
  bool includeHeaders = true,
}) =>
    ModelProviderEntry.fromRaw(_rawProvider(
        id: id,
        source: source,
        apiKey: apiKey,
        baseUrl: baseUrl,
        includeApiKey: includeApiKey,
        includeHeaders: includeHeaders));

ModelEntry get _model => _provider().models.single;

void main() {
  test('builds the verified allowlist from unsaved visible draft values', () {
    final provider = _provider();
    final payload = buildModelConnectivityPayload(
      provider: provider,
      modelId: '  model-old  ',
      draft: {
        'apiKey': 'draft-secret',
        'apiFormat': 'openai-chat-completions',
        'defaultKind': 'openai-compatible',
        'endpoints': {
          'baseURL': 'https://draft.invalid',
          'paths': {'openai-chat-completions': '/chat/completions'},
        },
        'headers': {'x-visible': 'draft-header'},
        'source': 'untrusted-ui-field',
        'unknownField': 'must-not-cross-boundary',
      },
    );

    expect(payload.keys,
        containsAll(['endpoints', 'apiKey', 'model', 'provider']));
    expect(payload['model'], 'model-old');
    expect(payload['apiKey'], 'draft-secret');
    expect(payload['endpoints'], {
      'baseURL': 'https://draft.invalid',
      'paths': {'openai-chat-completions': '/chat/completions'},
    });
    final requestProvider =
        (payload['provider'] as Map).cast<String, dynamic>();
    expect(
      requestProvider.keys.toSet(),
      {
        'apiFormat',
        'defaultKind',
        'endpoints',
        'headers',
        'id',
        'modelSupportedFormats',
        'models',
      },
    );
    expect(requestProvider['headers'], {'x-visible': 'draft-header'});
    expect(requestProvider.containsKey('source'), isFalse);
    expect(requestProvider.containsKey('unknownField'), isFalse);
  });

  test('aggregates results and keeps empty response distinct', () {
    final aggregated = parseModelConnectivityResponse({
      'results': [
        {
          'success': false,
          'error': {'message': '  refused  '},
        },
        {
          'success': false,
          'error': {'message': 'refused'},
        },
        {
          'success': false,
          'error': {'message': 'timeout'},
        },
      ],
    });
    expect(aggregated.success, isFalse);
    expect(aggregated.failureReason, 'refused; timeout');
    final empty = parseModelConnectivityResponse({'results': []});
    expect(empty.success, isFalse);
    expect(empty.failureReason, isNull);
    expect(empty.noEndpointResult, isTrue);
    expect(
      parseModelConnectivityResponse({
        'results': [
          {
            'success': false,
            'error': {'message': 'failed'}
          },
          {'success': true},
        ],
      }).success,
      isTrue,
    );
  });

  test('does not invent absent optional fields', () {
    final provider = ModelProviderEntry.fromRaw({
      'id': 'minimal',
      'name': 'Minimal',
      'source': 'custom',
    });
    final payload = buildModelConnectivityPayload(
      provider: provider,
      modelId: 'model-a',
    );
    expect(payload.containsKey('apiKey'), isFalse);
    expect(payload.containsKey('endpoints'), isFalse);
    final requestProvider =
        (payload['provider'] as Map).cast<String, dynamic>();
    expect(requestProvider.keys, {'id'});
  });

  test('tests through model-provider without saving and redacts key in errors',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async {
      expect(channel, Channels.modelProvider);
      expect(method, 'testModelConnectivity');
      return {
        'results': [
          {
            'success': false,
            'error': {'message': 'bad confirmed-secret'},
          },
        ],
      };
    };
    final controller = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
    );
    addTearDown(controller.dispose);

    final outcome = await controller.testModel(
      provider: _provider(),
      model: _model,
    );
    expect(outcome.success, isFalse);
    expect(outcome.failureReason, 'bad [redacted]');
    expect(bridge.channels.calls.where((c) => c.method == 'save'), isEmpty);
    expect(controller.resultFor('custom-provider', 'model-old'), outcome);
    final call = bridge.channels.calls
        .singleWhere((c) => c.method == 'testModelConnectivity');
    final payload = call.args.single as Map;
    expect(payload['model'], 'model-old');
    expect(payload['apiKey'], 'confirmed-secret');
  });

  test('deduplicates pending model and drops a superseded draft result',
      () async {
    final bridge = FeatureBridge();
    final firstGate = Completer<void>();
    var calls = 0;
    bridge.channels.handler = (channel, method, args) async {
      calls++;
      if (calls == 1) {
        await firstGate.future;
        return {
          'results': [
            {
              'success': false,
              'error': {'message': 'old result'}
            },
          ],
        };
      }
      return {
        'results': [
          {'success': true},
        ],
      };
    };
    final controller = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
    );
    addTearDown(controller.dispose);
    final provider = _provider();
    final first = controller.testModel(
      provider: provider,
      model: _model,
      draft: {
        'headers': {'x-draft': 'one'}
      },
    );
    final duplicate = controller.testModel(
      provider: provider,
      model: _model,
      draft: {
        'headers': {'x-draft': 'one'}
      },
    );
    expect(identical(first, duplicate), isTrue);
    expect(controller.isTesting(provider.id, _model.id), isTrue);

    final second = controller.testModel(
      provider: provider,
      model: _model,
      draft: {
        'headers': {'x-draft': 'two'}
      },
    );
    expect(controller.isTesting(provider.id, _model.id), isTrue);
    firstGate.complete();
    final firstOutcome = await first;
    expect(firstOutcome.failureReason, 'old result');
    expect(controller.resultFor(provider.id, _model.id)?.failureReason,
        isNot('old result'));
    expect((await second).success, isTrue);
    expect(calls, 2);
  });

  test('dispose isolates late channel completion', () async {
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    bridge.channels.handler = (channel, method, args) async {
      await gate.future;
      return {
        'results': [
          {'success': true}
        ]
      };
    };
    final controller = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
    );
    final pending = controller.testModel(provider: _provider(), model: _model);
    controller.dispose();
    gate.complete();
    expect((await pending).success, isTrue);
    expect(controller.attemptFor('custom-provider', 'model-old'), isNull);
  });

  test('uses dynamic resolver only for parsed zcode-plan endpoints', () async {
    final bridge = FeatureBridge();
    var resolverCalls = 0;
    var rpcCalls = 0;
    bridge.channels.handler = (channel, method, args) async {
      rpcCalls++;
      return {
        'results': [
          {'success': true}
        ]
      };
    };
    final controller = ModelConnectivityController(
      session: bridge,
      scopeKey: 'device|workspace',
      dynamicHeadersResolver: (provider, config) async {
        resolverCalls++;
        return {'x-captcha-certify': 'synthetic-certify'};
      },
    );
    addTearDown(controller.dispose);

    // The name includes coding-plan, but its parsed endpoint is ordinary.
    expect(
        (await controller.testModel(
                provider: _provider(id: 'coding-plan-label'), model: _model))
            .success,
        isTrue);
    expect(resolverCalls, 0);
    expect(rpcCalls, 1);

    final plan = _provider(
      id: 'custom-provider',
      includeApiKey: false,
      baseUrl: 'https://synthetic.invalid/api/v1/zcode-plan',
    );
    expect(
        (await controller.testModel(provider: plan, model: plan.models.single))
            .success,
        isTrue);
    expect(resolverCalls, 1);
    expect(rpcCalls, 2);
    final call = bridge.channels.calls
        .lastWhere((item) => item.method == 'testModelConnectivity');
    final providerPayload = (call.args.single as Map)['provider'] as Map;
    expect(
        providerPayload['headers']['x-captcha-certify'], 'synthetic-certify');
    expect((call.args.single as Map).containsKey('apiKey'), isFalse);
  });
}
