import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';
import '../ui/fake_features.dart';

Map<String, dynamic> _provider(String id, {bool enabled = true}) => {
      'id': id,
      'name': 'Provider $id',
      'enabled': enabled,
      'apiFormat': 'anthropic',
      'source': 'custom',
      'defaultKind': 'chat',
      'apiKey': 'secret-value',
      'endpoints': {
        'baseURL': 'https://synthetic.invalid',
        'paths': {'anthropic': '/v1/messages'},
      },
      'models': [
        {
          'id': '$id-model',
          'name': 'Model $id',
          'kinds': ['chat'],
          'defaultKind': 'chat',
          'modalities': {
            'input': ['text'],
            'output': ['text'],
          },
          'contextWindow': 200000,
          'maxOutputTokens': 8192,
          'reasoning': {
            'defaultLevel': 'high',
            'levels': {'low': {}, 'high': {}, 'max': {}},
          },
          'priority': 10,
          'modified': false,
        }
      ],
      'createdAt': 1,
      'updatedAt': 2,
    };

void main() {
  test('catalog loads official getAll providers and hides secret material',
      () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      return [
        _provider('a'),
        _provider('b', enabled: false),
      ];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();

    expect(
        calls.any(
            (call) => call.$1 == Channels.modelProvider && call.$2 == 'getAll'),
        isTrue);
    expect(calls.firstWhere((call) => call.$1 == Channels.modelProvider).$3,
        isEmpty);
    expect(catalog.status, ModelProviderCatalogStatus.loaded);
    expect(catalog.items.length, 2);
    expect(catalog.items.first.models.single.name, 'Model a');
    expect(catalog.items.first.models.single.contextWindow, 200000);
    expect(catalog.items.first.models.single.reasoningLevels,
        ['high', 'low', 'max']);
    expect(catalog.items.first.hasApiKey, isTrue);
    expect(catalog.items.last.enabled, isFalse);
  });

  test('errors keep prior data, retry clears the failure', () async {
    final bridge = FeatureBridge();
    var failing = false;
    bridge.channels.handler = (channel, method, args) async {
      if (failing) throw StateError('offline');
      return [_provider('kept')];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    expect(catalog.status, ModelProviderCatalogStatus.loaded);
    expect(catalog.items.single.id, 'kept');

    failing = true;
    await catalog.refresh();
    expect(catalog.status, ModelProviderCatalogStatus.error);
    expect(catalog.error, isNotNull);
    expect(catalog.items.single.id, 'kept');

    failing = false;
    await catalog.refresh();
    expect(catalog.status, ModelProviderCatalogStatus.loaded);
    expect(catalog.error, isNull);
  });

  test('late response after dispose or regeneration is discarded', () async {
    final bridge = FeatureBridge();
    final completer = Completer<Object?>();
    bridge.channels.handler = (channel, method, args) => completer.future;

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    // Disposed below exactly once; addTearDown would double-dispose.
    final pending = catalog.refresh();
    expect(catalog.status, ModelProviderCatalogStatus.loading);
    catalog.dispose();
    completer.complete([_provider('late')]);
    await pending;

    expect(catalog.status, ModelProviderCatalogStatus.loading);
    expect(catalog.items, isEmpty);
  });

  test('model save sends the whole official provider and refreshes', () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    Map<String, dynamic>? saved;
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'save') {
        saved = args.single as Map<String, dynamic>;
        return saved;
      }
      return [if (saved != null) saved! else _provider('a')];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final provider = catalog.items.single;

    final models = [
      for (final model in provider.models) {...model.raw, 'name': 'Updated'},
    ];
    final ok = await catalog.saveProviderModels(provider, models);

    expect(ok, isTrue);
    expect(catalog.saveError('a'), isNull);
    expect(catalog.items.single.models.single.name, 'Updated');
    final save = calls.firstWhere((call) => call.$2 == 'save');
    expect(save.$1, Channels.modelProvider);
    final payload = save.$3.single as Map<String, dynamic>;
    expect(payload['id'], 'a');
    expect(payload['apiKey'], 'secret-value');
    expect((payload['models'] as List).single['name'], 'Updated');
    expect(calls.where((call) => call.$2 == 'getAll'), hasLength(2));
  });

  test('failed model save keeps the prior catalog and can retry', () async {
    final bridge = FeatureBridge();
    var saveShouldFail = true;
    Map<String, dynamic>? saved;
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'save') {
        if (saveShouldFail) throw StateError('save rejected');
        saved = args.single as Map<String, dynamic>;
        return saved;
      }
      if (saved == null) return [_provider('a')];
      return [saved];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final provider = catalog.items.single;
    final models = [
      for (final model in provider.models) {...model.raw, 'name': 'Updated'},
    ];

    expect(await catalog.saveProviderModels(provider, models), isFalse);
    expect(catalog.saveError('a'), isNotNull);
    expect(catalog.status, ModelProviderCatalogStatus.loaded);
    expect(catalog.items.single.models.single.name, 'Model a');

    saveShouldFail = false;
    expect(await catalog.saveProviderModels(provider, models), isTrue);
    expect(catalog.saveError('a'), isNull);
    expect(catalog.items.single.models.single.name, 'Updated');
    expect(calls.where((call) => call.$2 == 'save'), hasLength(2));
  });

  test('save is deduplicated per provider and late work does not leak',
      () async {
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        await gate.future;
        return args.single;
      }
      return [_provider('a')];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final provider = catalog.items.single;
    final models = [
      for (final model in provider.models) {...model.raw},
    ];
    final first = catalog.saveProviderModels(provider, models);
    expect(catalog.isSaving('a'), isTrue);
    expect(await catalog.saveProviderModels(provider, models), isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(catalog.isSaving('a'), isFalse);
  });

  test('custom provider delete refreshes while protected providers are blocked',
      () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var deleted = false;
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'delete') {
        deleted = true;
        return null;
      }
      if (deleted) return [];
      return [
        _provider('custom'),
        {..._provider('builtin'), 'id': 'builtin:zai', 'source': 'builtin'},
      ];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    expect(catalog.items, hasLength(2));
    expect(catalog.canDelete(catalog.items.first), isTrue);
    expect(catalog.canDelete(catalog.items.last), isFalse);

    expect(await catalog.deleteProvider(catalog.items.last), isFalse);
    expect(calls.where((call) => call.$2 == 'delete'), isEmpty);

    expect(await catalog.deleteProvider(catalog.items.first), isTrue);
    final deletion = calls.firstWhere((call) => call.$2 == 'delete');
    expect(deletion.$1, Channels.modelProvider);
    expect(deletion.$3, ['custom']);
    expect(catalog.errorOperation('custom'), 'delete');
    expect(catalog.items, isEmpty);
  });

  test('provider delete failure keeps the prior catalog and records error',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'delete') throw StateError('delete rejected');
      return [_provider('custom')];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();

    expect(await catalog.deleteProvider(catalog.items.single), isFalse);
    expect(catalog.saveError('custom'), isNotNull);
    expect(catalog.items.single.id, 'custom');
  });

  test('custom provider creation sends official endpoint schema and refreshes',
      () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'save') {
        final provider = args.single as Map<String, dynamic>;
        return provider;
      }
      final save = calls.where((call) => call.$2 == 'save').toList();
      return [if (save.isEmpty) ...const [] else save.single.$3.single];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);

    final created = await catalog.createCustomProvider(
      name: '',
      baseURL: 'https://synthetic.invalid/v1',
      apiKey: 'secret-create',
      apiFormat: 'openai-chat-completions',
      modelName: 'Test Model',
      contextWindow: 200000,
    );

    expect(created, isTrue);
    expect(catalog.creationError, isNull);
    final save = calls.singleWhere((call) => call.$2 == 'save');
    expect(save.$1, Channels.modelProvider);
    final payload = save.$3.single as Map<String, dynamic>;
    expect(payload['name'], 'New provider');
    expect(payload['source'], 'custom');
    expect(payload['apiFormat'], 'openai-chat-completions');
    expect(payload['defaultKind'], 'openai-compatible');
    expect(payload['apiKeyRequired'], isTrue);
    expect(
      (payload['endpoints'] as Map)['paths'],
      {
        'openai-chat-completions': '/chat/completions',
      },
    );
    expect((payload['models'] as List).single['id'], 'Test Model');
    expect(catalog.items.single.name, 'New provider');
    expect(catalog.items.single.models.single.contextWindow, 200000);
  });

  test('provider creation failure retains catalog and records retryable error',
      () async {
    final bridge = FeatureBridge();
    var fail = true;
    Map<String, dynamic>? saved;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        if (fail) throw StateError('create rejected');
        saved = args.single as Map<String, dynamic>;
        return saved;
      }
      return [if (saved != null) saved!];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);

    expect(
      await catalog.createCustomProvider(
        name: 'Broken',
        baseURL: 'https://synthetic.invalid/v1',
        apiKey: 'secret-create',
        apiFormat: 'anthropic-messages',
        modelName: 'Test Model',
        contextWindow: 200000,
      ),
      isFalse,
    );
    expect(catalog.creationError, isNotNull);
    expect(catalog.items, isEmpty);
    expect(catalog.isCreatingProvider, isFalse);

    fail = false;
    expect(
      await catalog.createCustomProvider(
        name: 'Recovered',
        baseURL: 'https://synthetic.invalid/v1',
        apiKey: '',
        apiFormat: 'anthropic-messages',
        modelName: 'Test Model',
        contextWindow: 200000,
      ),
      isTrue,
    );
    expect(catalog.creationError, isNull);
    expect(catalog.items.single.name, 'Recovered');
  });

  test('provider display order loads, saves authoritative order and refreshes',
      () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var order = ['c', 'a', 'b'];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'getDisplayOrder') return order;
      if (method == 'saveDisplayOrder') {
        order = List<String>.from(
            (args.single as Map<String, dynamic>)['providerIds'] as List);
        return null;
      }
      return [
        for (final id in order) {..._provider(id), 'source': 'custom'},
      ];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    expect(catalog.displayOrder, ['c', 'a', 'b']);
    expect([for (final item in catalog.items) item.id], ['c', 'a', 'b']);

    expect(await catalog.reorderProvider(catalog.items[1], -1), isTrue);
    final save = calls.singleWhere((call) => call.$2 == 'saveDisplayOrder');
    expect(save.$1, Channels.modelProvider);
    expect((save.$3.single as Map)['providerIds'], ['a', 'c', 'b']);
    expect(catalog.displayOrder, ['a', 'c', 'b']);
    expect([for (final item in catalog.items) item.id], ['a', 'c', 'b']);
  });

  test('display order failure restores prior rows and records retry error',
      () async {
    final bridge = FeatureBridge();
    var shouldFail = true;
    var order = ['a', 'b'];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'getDisplayOrder') return order;
      if (method == 'saveDisplayOrder') {
        if (shouldFail) throw StateError('order rejected');
        order = List<String>.from(
            (args.single as Map<String, dynamic>)['providerIds'] as List);
        return null;
      }
      return [
        for (final id in order) {..._provider(id), 'source': 'custom'}
      ];
    };

    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();

    expect(await catalog.reorderProvider(catalog.items.first, 1), isFalse);
    expect(catalog.saveError('a'), isNotNull);
    expect(catalog.errorOperation('a'), 'display-order');
    expect([for (final item in catalog.items) item.id], ['a', 'b']);
    expect(catalog.displayOrder, ['a', 'b']);

    shouldFail = false;
    expect(await catalog.reorderProvider(catalog.items.first, 1), isTrue);
    expect(catalog.saveError('a'), isNull);
    expect([for (final item in catalog.items) item.id], ['b', 'a']);
  });

  test('provider draft commit can clear legacy headers explicitly', () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    Map<String, dynamic>? saved;
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (method == 'save') {
        saved = Map<String, dynamic>.from(args.single as Map);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [
        saved ?? _provider('headers')
          ..addAll({
            'headers': {'x': 'secret'}
          })
      ];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'A|workspace');
    addTearDown(catalog.dispose);
    final provider = ModelProviderEntry.fromRaw({
      ..._provider('headers'),
      'source': 'custom',
      'headers': {'x': 'secret'},
    });
    expect(
      await catalog.saveProviderDraft(
        provider,
        {'name': 'updated'},
        clearHeaders: true,
      ),
      isTrue,
    );
    final payload = calls.singleWhere((call) => call.$2 == 'save').$3.single
        as Map<String, dynamic>;
    expect(payload.containsKey('headers'), isFalse);
  });
}
