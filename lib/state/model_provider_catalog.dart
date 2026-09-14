import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/conversation_bridge.dart';

enum ModelProviderCatalogStatus { idle, loading, loaded, error }

class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.name,
    required this.kinds,
    required this.defaultKind,
    required this.inputModalities,
    required this.outputModalities,
    required this.contextWindow,
    required this.maxOutputTokens,
    required this.reasoningDefaultLevel,
    required this.reasoningLevels,
    required this.priority,
    required this.modified,
    required this.raw,
  });

  factory ModelEntry.fromRaw(Map raw) {
    final originalRaw = Map<String, dynamic>.from(raw);
    final map = raw.cast<String, dynamic>();
    List<String> strings(Object? value) => value is List
        ? [
            for (final item in value)
              if (item is String) item
          ]
        : const [];
    final reasoning = map['reasoning'] is Map
        ? (map['reasoning'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final levels = reasoning['levels'] is Map
        ? (reasoning['levels'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final modalities = map['modalities'] is Map
        ? (map['modalities'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return ModelEntry(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? map['id'] ?? ''}',
      kinds: strings(map['kinds']),
      defaultKind: '${map['defaultKind'] ?? ''}',
      inputModalities: strings(modalities['input']).isNotEmpty
          ? strings(modalities['input'])
          : strings(map['inputModalities']),
      outputModalities: strings(modalities['output']).isNotEmpty
          ? strings(modalities['output'])
          : strings(map['outputModalities']),
      contextWindow:
          map['contextWindow'] is int ? map['contextWindow'] as int : null,
      maxOutputTokens:
          map['maxOutputTokens'] is int ? map['maxOutputTokens'] as int : null,
      reasoningDefaultLevel: '${reasoning['defaultLevel'] ?? ''}',
      reasoningLevels: [for (final key in levels.keys) key]..sort(),
      priority: map['priority'] is int ? map['priority'] as int : null,
      modified: map['modified'] == true,
      raw: originalRaw,
    );
  }

  final String id;
  final String name;
  final List<String> kinds;
  final String defaultKind;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final String reasoningDefaultLevel;
  final List<String> reasoningLevels;
  final int? priority;
  final bool modified;
  final Map<String, dynamic> raw;
}

class ModelProviderEntry {
  const ModelProviderEntry({
    required this.id,
    required this.name,
    required this.enabled,
    required this.apiFormat,
    required this.source,
    required this.defaultKind,
    required this.hasApiKey,
    required this.baseURL,
    required this.models,
    required this.raw,
  });

  factory ModelProviderEntry.fromRaw(Map raw) {
    final map = raw.cast<String, dynamic>();
    final endpoints = map['endpoints'] is Map
        ? (map['endpoints'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final models = map['models'] is List
        ? [
            for (final item in (map['models'] as List).whereType<Map>())
              ModelEntry.fromRaw(item),
          ]
        : const <ModelEntry>[];
    return ModelProviderEntry(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? map['id'] ?? ''}',
      enabled: map['enabled'] != false,
      apiFormat: '${map['apiFormat'] ?? ''}',
      source: '${map['source'] ?? ''}',
      defaultKind: '${map['defaultKind'] ?? ''}',
      // Never surface secret material in the UI layer.
      hasApiKey:
          map['apiKey'] is String && (map['apiKey'] as String).isNotEmpty,
      baseURL: endpoints['baseURL'] is String
          ? endpoints['baseURL'] as String
          : null,
      models: models,
      raw: map,
    );
  }

  final String id;
  final String name;
  final bool enabled;
  final String apiFormat;
  final String source;
  final String defaultKind;
  final bool hasApiKey;
  final String? baseURL;
  final List<ModelEntry> models;
  final Map<String, dynamic> raw;

  /// Official save is whole-provider. Rebuild only the model array on the
  /// original raw object so API keys/endpoint metadata are never projected
  /// through UI form state.
  Map<String, dynamic> withModels(List<Map<String, dynamic>> models) => {
        ...raw,
        'models': List<Map<String, dynamic>>.unmodifiable(models),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
}

/// Official `modelProviderService.getAll()` projection with whole-provider
/// model-row saves and custom-provider deletion.
class ModelProvidersCatalog extends ChangeNotifier {
  ModelProvidersCatalog({
    required this.session,
    required this.scopeKey,
  });

  final ConversationBridge session;
  final String scopeKey;

  int _generation = 0;
  Future<void>? _pending;
  bool _disposed = false;

  ModelProviderCatalogStatus status = ModelProviderCatalogStatus.idle;
  List<ModelProviderEntry> items = const [];
  Object? error;
  List<String> displayOrder = const [];
  final Set<String> _savingProviders = {};
  final Map<String, Object> _saveErrors = {};
  final Map<String, String> _errorOperations = {};
  bool _creatingProvider = false;
  Object? _creationError;

  bool isSaving(String providerId) => _savingProviders.contains(providerId);

  Object? saveError(String providerId) => _saveErrors[providerId];

  String? errorOperation(String providerId) => _errorOperations[providerId];

  bool get isCreatingProvider => _creatingProvider;

  Object? get creationError => _creationError;

  /// Official custom-provider form saves a complete endpoint provider and at
  /// least one model. `source` is always custom so the new row is deletable.
  Future<bool> createCustomProvider({
    required String name,
    required String baseURL,
    required String apiKey,
    required String apiFormat,
    required String modelName,
    required int contextWindow,
  }) async {
    if (_disposed || _creatingProvider) return false;
    final trimmedName = name.trim().isEmpty ? 'New provider' : name.trim();
    final trimmedBase = baseURL.trim();
    final trimmedModel = modelName.trim();
    if (trimmedBase.isEmpty || trimmedModel.isEmpty || contextWindow <= 0) {
      _creationError = StateError('base URL, model and context are required');
      notifyListeners();
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = switch (apiFormat) {
      'anthropic-messages' => '/v1/messages',
      'openai-chat-completions' => '/chat/completions',
      'openai-responses' => '/responses',
      _ => null,
    };
    final defaultKind = switch (apiFormat) {
      'anthropic-messages' => 'anthropic',
      'openai-chat-completions' || 'openai-responses' => 'openai-compatible',
      _ => null,
    };
    if (path == null || defaultKind == null) {
      _creationError = StateError('unsupported api format');
      notifyListeners();
      return false;
    }
    _creatingProvider = true;
    _creationError = null;
    notifyListeners();
    try {
      await session.channels.call(
        Channels.modelProvider,
        'save',
        [
          {
            'id': 'custom-$now',
            'name': trimmedName,
            'apiFormat': apiFormat,
            'source': 'custom',
            'apiKey': apiKey,
            'apiKeyRequired': apiKey.isNotEmpty,
            'defaultKind': defaultKind,
            'endpoints': {
              'baseURL': trimmedBase,
              'paths': {apiFormat: path},
            },
            'models': [
              {
                'id': trimmedModel,
                'name': trimmedModel,
                'kinds': [defaultKind],
                'defaultKind': defaultKind,
                'modalities': {
                  'input': ['text'],
                  'output': ['text'],
                },
                'contextWindow': contextWindow,
              }
            ],
            'createdAt': now,
            'updatedAt': now,
          }
        ],
        timeout: const Duration(seconds: 30),
      );
      await refresh();
      if (_disposed) return false;
      return status == ModelProviderCatalogStatus.loaded;
    } catch (value) {
      if (_disposed) return false;
      _creationError = value;
      notifyListeners();
      return false;
    } finally {
      _creatingProvider = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    status = ModelProviderCatalogStatus.loading;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.modelProvider,
          'getAll',
          const [],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed || generation != _generation) return;
        items = raw is List
            ? [
                for (final item in raw.whereType<Map>())
                  ModelProviderEntry.fromRaw(item),
              ]
            : const <ModelProviderEntry>[];
        try {
          final order = await session.channels.call(
            Channels.modelProvider,
            'getDisplayOrder',
            const [],
            timeout: const Duration(seconds: 30),
          );
          if (_disposed || generation != _generation) return;
          displayOrder = order is List
              ? [
                  for (final id in order)
                    if (id is String) id
                ]
              : const <String>[];
        } catch (_) {
          if (_disposed || generation != _generation) return;
          // Official load treats display-order failure as non-fatal and falls
          // back to the authoritative getAll sequence.
          displayOrder = const <String>[];
        }
        _sortItems();
        status = ModelProviderCatalogStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = ModelProviderCatalogStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  void _sortItems() {
    if (displayOrder.isEmpty || items.length < 2) return;
    final rank = <String, int>{
      for (var index = 0; index < displayOrder.length; index++)
        displayOrder[index]: index,
    };
    items = [...items]..sort((left, right) {
        final leftRank = rank[left.id] ?? displayOrder.length;
        final rightRank = rank[right.id] ?? displayOrder.length;
        return leftRank.compareTo(rightRank);
      });
  }

  /// Official `modelProviderService.save(provider)` sends the whole provider.
  /// Success re-reads authoritative state; failure keeps the previous list.
  Future<bool> saveProviderModels(
    ModelProviderEntry provider,
    List<Map<String, dynamic>> models,
  ) async {
    if (_disposed || _savingProviders.contains(provider.id)) return false;
    _savingProviders.add(provider.id);
    _saveErrors.remove(provider.id);
    _errorOperations[provider.id] = 'save';
    notifyListeners();
    try {
      await session.channels.call(
        Channels.modelProvider,
        'save',
        [provider.withModels(models)],
        timeout: const Duration(seconds: 30),
      );
      await refresh();
      if (_disposed) return false;
      return status == ModelProviderCatalogStatus.loaded;
    } catch (value) {
      if (_disposed) return false;
      _saveErrors[provider.id] = value;
      notifyListeners();
      return false;
    } finally {
      _savingProviders.remove(provider.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// Saves the complete currently visible provider draft and accepts it only
  /// after an authoritative `getAll` read-back. The draft is merged onto the
  /// original raw provider so fields the editor does not expose (including
  /// model metadata and endpoint path maps) survive unchanged.
  Future<bool> saveProviderDraft(
    ModelProviderEntry provider,
    Map<String, dynamic> draft, {
    bool clearHeaders = false,
  }) async {
    if (_disposed || _savingProviders.contains(provider.id)) return false;
    _savingProviders.add(provider.id);
    _saveErrors.remove(provider.id);
    _errorOperations[provider.id] = 'save';
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        ..._cloneMap(provider.raw),
        ..._cloneMap(draft),
        'id': provider.id,
        // Provider source controls deletion and plan semantics; it is not an
        // editable form field and must remain authoritative.
        if (provider.raw.containsKey('source'))
          'source': _clone(provider.raw['source']),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      // Official S8/B commits replace an existing headers field with
      // undefined. JSON serialization omits that key, which is the delete
      // operation. Keep this explicit so connectivity tests still preserve
      // the unedited headers from the visible provider.
      if (clearHeaders) payload.remove('headers');
      await session.channels.call(
        Channels.modelProvider,
        'save',
        [payload],
        timeout: const Duration(seconds: 30),
      );
      await refresh();
      if (_disposed) return false;
      final found = items.any((item) => item.id == provider.id);
      if (status != ModelProviderCatalogStatus.loaded || !found) {
        throw StateError('provider readback failed');
      }
      return true;
    } catch (value) {
      if (_disposed) return false;
      _saveErrors[provider.id] = _redactProviderError(value, provider, draft);
      notifyListeners();
      return false;
    } finally {
      _savingProviders.remove(provider.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// Convenience spelling used by provider editor widgets.
  Future<bool> saveProvider(
    ModelProviderEntry provider,
    Map<String, dynamic> draft, {
    bool clearHeaders = false,
  }) =>
      saveProviderDraft(provider, draft, clearHeaders: clearHeaders);

  /// Official `deleteProvider` is gated to custom configurations. Built-in,
  /// preset, coding-plan and team-plan providers are intentionally excluded.
  bool canDelete(ModelProviderEntry provider) => provider.source == 'custom';

  Future<bool> deleteProvider(ModelProviderEntry provider) async {
    if (_disposed ||
        provider.id.isEmpty ||
        !canDelete(provider) ||
        _savingProviders.contains(provider.id)) {
      return false;
    }
    _savingProviders.add(provider.id);
    _saveErrors.remove(provider.id);
    _errorOperations[provider.id] = 'delete';
    notifyListeners();
    try {
      await session.channels.call(
        Channels.modelProvider,
        'delete',
        [provider.id],
        timeout: const Duration(seconds: 30),
      );
      await refresh();
      if (_disposed) return false;
      return status == ModelProviderCatalogStatus.loaded;
    } catch (value) {
      if (_disposed) return false;
      _saveErrors[provider.id] = value;
      notifyListeners();
      return false;
    } finally {
      _savingProviders.remove(provider.id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> reorderProvider(
    ModelProviderEntry provider,
    int delta,
  ) async {
    if (_disposed ||
        provider.id.isEmpty ||
        delta == 0 ||
        items.length < 2 ||
        _savingProviders.contains(provider.id)) {
      return false;
    }
    final ids = [for (final item in items) item.id];
    final currentIndex = ids.indexOf(provider.id);
    if (currentIndex < 0) return false;
    final targetIndex = (currentIndex + delta).clamp(0, ids.length - 1);
    if (targetIndex == currentIndex) return true;
    final previousItems = items;
    final previousOrder = displayOrder;
    ids.insert(targetIndex, ids.removeAt(currentIndex));
    _savingProviders.add(provider.id);
    _saveErrors.remove(provider.id);
    _errorOperations[provider.id] = 'display-order';
    items = [
      for (final id in ids) items.firstWhere((item) => item.id == id),
    ];
    displayOrder = ids;
    notifyListeners();
    try {
      await session.channels.call(
        Channels.modelProvider,
        'saveDisplayOrder',
        [
          {
            'providerIds': ids,
            'updatedAt': DateTime.now().millisecondsSinceEpoch
          },
        ],
        timeout: const Duration(seconds: 30),
      );
      await refresh();
      if (_disposed) return false;
      return status == ModelProviderCatalogStatus.loaded;
    } catch (value) {
      if (_disposed) return false;
      items = previousItems;
      displayOrder = previousOrder;
      _saveErrors[provider.id] = value;
      notifyListeners();
      return false;
    } finally {
      _savingProviders.remove(provider.id);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

dynamic _clone(dynamic value) {
  if (value is Map) return _cloneMap(value);
  if (value is List) return [for (final item in value) _clone(item)];
  return value;
}

Map<String, dynamic> _cloneMap(Map value) => {
      for (final entry in value.entries) '${entry.key}': _clone(entry.value),
    };

Object _redactProviderError(
  Object error,
  ModelProviderEntry provider,
  Map<String, dynamic> draft,
) {
  final secrets = <String>{};
  void collect(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'apiKey' ||
            entry.key == 'authorization' ||
            entry.key == 'token') {
          if (entry.value is String && (entry.value as String).isNotEmpty) {
            secrets.add(entry.value as String);
          }
        }
        collect(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        collect(item);
      }
    }
  }

  collect(provider.raw);
  collect(draft);
  var message = '$error';
  for (final secret in secrets) {
    message = message.replaceAll(secret, '[redacted]');
  }
  return StateError(message.isEmpty ? 'provider save failed' : message);
}
