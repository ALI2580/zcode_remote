import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';
import 'package:zcode_remote/ui/model_provider_editor.dart';

import 'fake_features.dart';

Map<String, dynamic> _rawProvider() => {
      'id': 'provider-a',
      'name': 'Provider A',
      'source': 'custom',
      'enabled': true,
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'apiKey': 'confirmed-key',
      'headers': {'x-confirmed': 'confirmed-header'},
      'endpoints': {
        'baseURL': 'https://confirmed.invalid',
        'paths': {'anthropic-messages': '/v1/messages'},
      },
      'modelSupportedFormats': ['text'],
      'models': [
        {
          'id': 'confirmed-model',
          'name': 'Confirmed model',
          'kinds': ['anthropic'],
          'defaultKind': 'anthropic',
          'modalities': {
            'input': ['text'],
            'output': ['text'],
          },
          'contextWindow': 128000,
          'maxOutputTokens': 8192,
          'reasoning': {
            'defaultLevel': 'high',
            'levels': {'high': {}},
          },
        }
      ],
      'unexposedMetadata': {'mustSurvive': true},
    };

ModelProviderEntry get _provider => ModelProviderEntry.fromRaw(_rawProvider());

Future<void> _pumpEditor(
  WidgetTester tester, {
  required ModelProvidersCatalog catalog,
  required ModelConnectivityController connectivity,
  ModelProviderEditorSaved? onSaved,
  VoidCallback? onCancel,
  VoidCallback? onComposerRefresh,
  bool commitProviderFields = false,
  bool cleanupOnDispose = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ModelProviderEditor(
      provider: _provider,
      catalog: catalog,
      connectivity: connectivity,
      onSaved: onSaved,
      onCancel: onCancel,
      onComposerRefresh: onComposerRefresh,
      commitProviderFields: commitProviderFields,
      cleanupOnDispose: cleanupOnDispose,
    ),
  ));
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

TextField _field(WidgetTester tester, String label) => tester.widget(
      find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == label),
    ) as TextField;

Finder _fieldFinder(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

void main() {
  testWidgets('tests the complete unsaved provider draft without saving',
      (tester) async {
    final bridge = FeatureBridge();
    final calls = <({String method, List<Object?> args})>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((method: method, args: args));
      if (method == 'testModelConnectivity') {
        return {
          'results': [
            {'success': true}
          ]
        };
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
    );

    _field(tester, 'Base URL').controller!.text = 'https://draft.invalid/api';
    _field(tester, 'API key').controller!.text = 'draft-key';
    final testButton = find.byTooltip('Test model');
    await _reveal(tester, testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    final tests = calls.where((call) => call.method == 'testModelConnectivity');
    expect(tests, hasLength(1));
    final payload = tests.single.args.single as Map;
    expect(payload['model'], 'confirmed-model');
    expect(payload['apiKey'], 'draft-key');
    expect(payload['endpoints'], {
      'baseURL': 'https://draft.invalid/api',
      'paths': {'anthropic-messages': '/v1/messages'},
    });
    final requestProvider = payload['provider'] as Map;
    expect(requestProvider['headers'], {'x-confirmed': 'confirmed-header'});
    expect(requestProvider['name'], isNull);
    expect(calls.where((call) => call.method == 'save'), isEmpty);
  });

  testWidgets('cancel leaves the complete draft local and sends no save',
      (tester) async {
    final bridge = FeatureBridge();
    final methods = <String>[];
    bridge.channels.handler = (channel, method, args) async {
      methods.add(method);
      return method == 'getDisplayOrder' ? <String>[] : [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    var cancelled = false;
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
      onCancel: () => cancelled = true,
    );
    _field(tester, 'Name').controller!.text = 'Changed locally';
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    await _reveal(tester, cancel);
    await tester.tap(cancel);
    await tester.pump();
    expect(cancelled, isTrue);
    expect(methods, isNot(contains('save')));
  });

  testWidgets('save failure keeps editor and draft visible for retry',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') throw StateError('rejected confirmed-key');
      return method == 'getDisplayOrder' ? <String>[] : [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester, catalog: catalog, connectivity: connectivity);
    _field(tester, 'Name').controller!.text = 'Retry provider';
    final save = find.text('Save');
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Edit provider'), findsOneWidget);
    expect(find.text('Retry provider'), findsOneWidget);
    expect(find.textContaining('rejected [redacted]'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets(
      'cancel cleanup commits latest provider field but never commits model draft',
      (tester) async {
    final bridge = FeatureBridge();
    final saves = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        final saved = Map<String, dynamic>.from(args.single as Map);
        saves.add(saved);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saves.isEmpty ? _rawProvider() : saves.last];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    var cancelled = false;
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
      commitProviderFields: true,
      onCancel: () => cancelled = true,
    );

    _field(tester, 'Name').controller!.text = 'Exited provider';
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    await _reveal(tester, cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(saves, hasLength(1));
    expect(saves.single['name'], 'Exited provider');
    expect((saves.single['models'] as List).single['id'], 'confirmed-model');
    expect(saves.single.containsKey('headers'), isFalse);
  });

  testWidgets('provider section cleanup saves on unmount', (tester) async {
    final bridge = FeatureBridge();
    final saves = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        final saved = Map<String, dynamic>.from(args.single as Map);
        saves.add(saved);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saves.isEmpty ? _rawProvider() : saves.last];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
      commitProviderFields: true,
      cleanupOnDispose: true,
    );
    await tester.enterText(_fieldFinder('Name'), 'Switched provider');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single['name'], 'Switched provider');
    expect((saves.single['models'] as List).single['id'], 'confirmed-model');
  });

  testWidgets('internal provider save suppresses cleanup duplicate',
      (tester) async {
    final bridge = FeatureBridge();
    final saves = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        final saved = Map<String, dynamic>.from(args.single as Map);
        saves.add(saved);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saves.isEmpty ? _rawProvider() : saves.last];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
      commitProviderFields: true,
      cleanupOnDispose: true,
    );
    _field(tester, 'Name').controller!.text = 'Explicitly saved';
    final save = find.text('Save');
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single['name'], 'Explicitly saved');
  });

  testWidgets('save reads back full provider and triggers composer callback',
      (tester) async {
    final bridge = FeatureBridge();
    final calls = <({String method, List<Object?> args})>[];
    Map<String, dynamic>? saved;
    bridge.channels.handler = (channel, method, args) async {
      calls.add((method: method, args: args));
      if (method == 'save') {
        saved = Map<String, dynamic>.from(args.single as Map);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saved ?? _rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    ModelProviderEntry? updated;
    var composerRefreshes = 0;
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
      onSaved: (provider) => updated = provider,
      onComposerRefresh: () => composerRefreshes++,
    );
    _field(tester, 'Name').controller!.text = 'Saved provider';
    _field(tester, 'Model ID').controller!.text = 'real-model-id';
    final save = find.text('Save');
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(updated?.name, 'Saved provider');
    expect(updated?.models.single.id, 'real-model-id');
    expect(composerRefreshes, 1);
    final saveCalls = calls.where((call) => call.method == 'save');
    expect(saveCalls, hasLength(1));
    final payload = saveCalls.single.args.single as Map;
    expect(payload['id'], 'provider-a');
    expect(payload['source'], 'custom');
    expect(payload['unexposedMetadata'], {'mustSurvive': true});
    expect((payload['models'] as List).single['id'], 'real-model-id');
    expect(calls.where((call) => call.method == 'getAll'), hasLength(1));
    expect(find.text('Edit provider'), findsOneWidget);
  });

  testWidgets('edited model id is sent verbatim when testing draft',
      (tester) async {
    final bridge = FeatureBridge();
    final testPayloads = <Map>[];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'testModelConnectivity') {
        testPayloads.add(args.single as Map);
        return {
          'results': [
            {'success': true}
          ]
        };
      }
      return method == 'getDisplayOrder' ? <String>[] : [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester, catalog: catalog, connectivity: connectivity);
    _field(tester, 'Model ID').controller!.text = 'explicit-provider-model';
    final testButton = find.byTooltip('Test model');
    await _reveal(tester, testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
    expect(testPayloads, hasLength(1));
    expect(testPayloads.single['model'], 'explicit-provider-model');
    expect((testPayloads.single['provider'] as Map)['models'].single['id'],
        'explicit-provider-model');
  });

  testWidgets('format draft synchronizes default kind and endpoint path',
      (tester) async {
    final bridge = FeatureBridge();
    Map? testPayload;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'testModelConnectivity') {
        testPayload = args.single as Map;
        return {
          'results': [
            {'success': true}
          ]
        };
      }
      return method == 'getDisplayOrder' ? <String>[] : [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester, catalog: catalog, connectivity: connectivity);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai-chat-completions').last);
    await tester.pump();
    final button = find.byTooltip('Test model');
    await _reveal(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
        (testPayload!['provider'] as Map)['defaultKind'], 'openai-compatible');
    expect(testPayload!['endpoints'], {
      'baseURL': 'https://confirmed.invalid',
      'paths': {'openai-chat-completions': '/chat/completions'},
    });
  });

  testWidgets('official provider fields commit on blur and escape rolls back',
      (tester) async {
    final bridge = FeatureBridge();
    final saves = <Map>[];
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        final saved = Map<String, dynamic>.from(args.single as Map);
        saves.add(saved);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saves.isEmpty ? _rawProvider() : saves.last];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    var refreshes = 0;
    await _pumpEditor(tester,
        catalog: catalog,
        connectivity: connectivity,
        commitProviderFields: true,
        onComposerRefresh: () => refreshes++);

    await tester.enterText(_fieldFinder('Name'), 'Blurred provider');
    await tester.tap(_fieldFinder('Base URL'));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.single['name'], 'Blurred provider');
    expect(saves.single.containsKey('headers'), isFalse,
        reason: 'S8 clears old headers only on a provider commit');
    expect(refreshes, 1);

    await tester.enterText(
        _fieldFinder('Base URL'), 'https://rolled-back.invalid');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_field(tester, 'Base URL').controller!.text,
        'https://confirmed.invalid');
    expect(saves, hasLength(1));
  });

  testWidgets('IME composition defers provider name Enter commit',
      (tester) async {
    final bridge = FeatureBridge();
    final methods = <String>[];
    bridge.channels.handler = (channel, method, args) async {
      methods.add(method);
      if (method == 'save') return args.single;
      if (method == 'getDisplayOrder') return <String>[];
      return [_rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester,
        catalog: catalog,
        connectivity: connectivity,
        commitProviderFields: true);
    final name = _field(tester, 'Name');
    await tester.tap(find.byWidget(name));
    name.controller!.value = const TextEditingValue(
      text: 'composing',
      composing: TextRange(start: 0, end: 9),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(methods, isNot(contains('save')));

    name.controller!.value = const TextEditingValue(text: 'committed');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(methods, contains('save'));
  });

  testWidgets('provider blur commits queue without losing a later key edit',
      (tester) async {
    final bridge = FeatureBridge();
    final firstSaveGate = Completer<void>();
    final saves = <Map>[];
    var saveCount = 0;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        final saved = Map<String, dynamic>.from(args.single as Map);
        saves.add(saved);
        saveCount++;
        if (saveCount == 1) await firstSaveGate.future;
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saves.isEmpty ? _rawProvider() : saves.last];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester,
        catalog: catalog,
        connectivity: connectivity,
        commitProviderFields: true);

    await tester.enterText(_fieldFinder('Name'), 'Queued provider');
    await tester.tap(_fieldFinder('API key'));
    await tester.pump();
    expect(saveCount, 1);

    await tester.enterText(_fieldFinder('API key'), 'latest-key');
    await tester.ensureVisible(_fieldFinder('Model ID'));
    await tester.tap(_fieldFinder('Model ID'));
    await tester.pump();
    firstSaveGate.complete();
    await tester.pumpAndSettle();

    expect(saves, hasLength(2));
    expect(saves.last['name'], 'Queued provider');
    expect(saves.last['apiKey'], 'latest-key');
  });

  testWidgets('model fields commit with optional name and required modalities',
      (tester) async {
    final bridge = FeatureBridge();
    Map<String, dynamic>? saved;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'save') {
        saved = Map<String, dynamic>.from(args.single as Map);
        return saved;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [saved ?? _rawProvider()];
    };
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(tester, catalog: catalog, connectivity: connectivity);

    _field(tester, 'Model name').controller!.clear();
    _field(tester, 'Max output tokens').controller!.text = '4096';
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'openai'));
    await tester.tap(find.widgetWithText(FilterChip, 'openai'));
    await tester.tap(find.widgetWithText(FilterChip, 'image'));
    final saveButton = find.text('Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final model = (saved!['models'] as List).single as Map;
    expect(model.containsKey('name'), isFalse);
    expect(model['kinds'], ['anthropic', 'openai']);
    expect(model['defaultKind'], 'anthropic');
    expect(model['contextWindow'], 128000);
    expect(model['maxOutputTokens'], 4096);
    expect(model['modalities'], {
      'input': ['text', 'image'],
      'output': ['text'],
    });
    expect(model['reasoning'], isNotNull);
  });

  testWidgets('editor gates honor read-only and context-only modes',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async =>
        method == 'getDisplayOrder' ? <String>[] : [_rawProvider()];
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'device|workspace');
    final connectivity = ModelConnectivityController(
        session: bridge, scopeKey: 'device|workspace');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    await _pumpEditor(
      tester,
      catalog: catalog,
      connectivity: connectivity,
    );
    await tester.pumpWidget(MaterialApp(
      home: ModelProviderEditor(
        provider: _provider,
        catalog: catalog,
        connectivity: connectivity,
        readOnlyEndpoints: true,
        readOnlyApiKey: true,
        nameEditable: false,
        modelsEditMode: 'context-window-only',
      ),
    ));
    await tester.pump();
    expect(_field(tester, 'Name').readOnly, isTrue);
    expect(_field(tester, 'Base URL').readOnly, isTrue);
    expect(_field(tester, 'API key').readOnly, isTrue);
    expect(_field(tester, 'Model ID').readOnly, isTrue);
    expect(
      tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'anthropic').first),
      isA<FilterChip>().having((chip) => chip.onSelected, 'onSelected', isNull),
    );
    expect(_field(tester, 'Context window').readOnly, isFalse);
    expect(_field(tester, 'Max output tokens').readOnly, isTrue);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'text').first),
      isA<FilterChip>().having((chip) => chip.onSelected, 'onSelected', isNull),
    );
    expect(find.byTooltip('Test model'), findsOneWidget);
  });
}
