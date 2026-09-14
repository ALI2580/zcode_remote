import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';
import 'model_captcha.dart';
import 'model_provider_catalog.dart';

/// A redacted projection of one model connectivity attempt.
///
/// The request payload is deliberately not retained here. It contains the
/// provider API key and is only held on the stack while the channel call is
/// in flight.
enum ModelConnectivityStatus { idle, pending, success, failure }

class ModelConnectivityOutcome {
  const ModelConnectivityOutcome({
    required this.success,
    this.failureReason,
    this.noEndpointResult = false,
  });

  final bool success;
  final String? failureReason;
  final bool noEndpointResult;

  bool get failed => !success;
}

class ModelConnectivityAttempt {
  const ModelConnectivityAttempt({
    required this.providerId,
    required this.source,
    required this.modelId,
    required this.status,
    this.outcome,
  });

  final String providerId;
  final String source;
  final String modelId;
  final ModelConnectivityStatus status;
  final ModelConnectivityOutcome? outcome;

  bool get pending => status == ModelConnectivityStatus.pending;
}

/// The official zcode-plan path obtains these values from its CAPTCHA flow.
/// The resolver is optional for ordinary API-key/custom providers and must
/// return headers produced by that real flow; the connectivity controller
/// never fabricates or skips these headers.
typedef ModelConnectivityDynamicHeadersResolver
    = FutureOr<Map<String, dynamic>?> Function(
        ModelProviderEntry provider, Map<String, dynamic> providerConfig);

/// Builds the resolver used by the existing plan endpoint gate. Keeping this
/// factory separate lets Settings/model editor wiring inject a fake CAPTCHA
/// adapter without changing the connectivity controller or provider editor.
ModelConnectivityDynamicHeadersResolver
    createModelConnectivityDynamicHeadersResolver({
  required ModelCaptchaService captcha,
  String? scopeKey,
}) {
  return (provider, providerConfig) {
    if (!isZcodePlanProvider(provider, providerConfig)) return null;
    return captcha.resolveHeaders(
      providerId: provider.id,
      scopeKey: scopeKey,
    );
  };
}

/// Frozen bundle `js-63.js` offset 118436 defines the two official origins
/// (`xu`/`Su`); `Vu` derives `/api/v1/zcode-plan` from them. The CAPTCHA
/// header handoff is recorded in `u14-captcha-headers.txt` lines 29-30
/// (`qlt` result consumed by `Sut`). These values are only defaults: callers
/// may inject an explicitly configured test origin.
const officialZcodePlanOpenAiBaseUrls = <String>[
  'https://zcode.z.ai/api/v1/zcode-plan',
  'https://zcode.chatglm.site/api/v1/zcode-plan',
];

/// Builds the allowlisted argument passed to
/// `model-provider.testModelConnectivity`.
///
/// [draft] represents the currently visible, unsaved provider form. A field
/// present in that map wins over the confirmed provider value, including an
/// intentionally empty API key. [readOnlyEndpoints] can be supplied when the
/// form is explicitly locked to server endpoints.
Map<String, dynamic> buildModelConnectivityPayload({
  required ModelProviderEntry provider,
  required String modelId,
  Map<String, dynamic>? draft,
  Map<String, dynamic>? readOnlyEndpoints,
  Map<String, dynamic>? dynamicHeaders,
}) {
  final source = provider.raw;
  final visible = <String, dynamic>{
    ...source,
    if (draft != null) ...draft,
  };
  final endpointsValue =
      readOnlyEndpoints ?? _valueOr(visible, 'endpoints', source['endpoints']);
  final endpoints = _mapCopy(endpointsValue);
  final apiKeyValue = _stringValue(visible, 'apiKey');
  final hasHeaders = visible['headers'] is Map || dynamicHeaders != null;
  final baseHeaders = _mapCopy(_valueOr(visible, 'headers', source['headers']));
  final headers = baseHeaders ?? <String, dynamic>{};
  if (dynamicHeaders != null) {
    headers.addAll(_deepCopyMap(dynamicHeaders));
  }

  // Keep this list aligned with the verified official request shape. In
  // particular, source/createdAt/updatedAt and unknown UI fields are omitted.
  final providerPayload = <String, dynamic>{'id': provider.id};
  final apiFormat = _valueOr(visible, 'apiFormat', source['apiFormat']);
  final defaultKind = _valueOr(visible, 'defaultKind', source['defaultKind']);
  if (apiFormat != null) providerPayload['apiFormat'] = _deepCopy(apiFormat);
  if (defaultKind != null) {
    providerPayload['defaultKind'] = _deepCopy(defaultKind);
  }
  if (endpoints != null) providerPayload['endpoints'] = endpoints;
  if (hasHeaders) providerPayload['headers'] = headers;
  final models = _listCopy(_valueOr(visible, 'models', source['models']));
  if (models != null) providerPayload['models'] = models;
  final supportedFormats = _valueOr(
      visible, 'modelSupportedFormats', source['modelSupportedFormats']);
  if (supportedFormats != null) {
    providerPayload['modelSupportedFormats'] = _deepCopy(supportedFormats);
  }

  final payload = <String, dynamic>{
    'model': modelId.trim(),
    'provider': providerPayload,
  };
  if (endpoints != null) payload['endpoints'] = endpoints;
  if (apiKeyValue != null) payload['apiKey'] = apiKeyValue;
  return payload;
}

/// A conservative copy used to ensure mutable fake responses cannot mutate a
/// visible provider draft while an attempt is running.
dynamic _deepCopy(dynamic value) {
  if (value is Map) return _deepCopyMap(value);
  if (value is List) return [for (final item in value) _deepCopy(item)];
  return value;
}

Map<String, dynamic> _deepCopyMap(Map value) => {
      for (final entry in value.entries) '${entry.key}': _deepCopy(entry.value),
    };

Map<String, dynamic>? _mapCopy(dynamic value) =>
    value is Map ? _deepCopyMap(value) : null;

List<dynamic>? _listCopy(dynamic value) =>
    value is List ? [for (final item in value) _deepCopy(item)] : null;

dynamic _valueOr(Map<String, dynamic> map, String key, dynamic fallback) =>
    map.containsKey(key) ? map[key] : fallback;

String? _stringValue(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String
      ? value
      : value == null
          ? null
          : '$value';
}

/// Detects the official plan endpoint family used by the dynamic CAPTCHA
/// header flow. Custom API-key endpoints remain on the ordinary path.
bool isZcodePlanProvider(
  ModelProviderEntry provider,
  Map<String, dynamic> providerConfig, {
  Iterable<String> officialPlanBaseUrls = officialZcodePlanOpenAiBaseUrls,
}) {
  // The official NQ gate parses the OpenAI and Anthropic endpoint selected by
  // `vo`/`aut`, then applies `iut` to that URL. Names and source labels are
  // intentionally ignored: an ordinary provider may contain “coding-plan”
  // in its id, while a custom provider may point at the plan endpoint.
  return _endpointCandidates(providerConfig, 'openai-compatible')
          .followedBy(_endpointCandidates(providerConfig, 'anthropic-messages'))
          .any((value) => _isZcodePlanEndpoint(value, officialPlanBaseUrls)) ||
      _endpointCandidates(providerConfig, 'openai')
          .followedBy(_endpointCandidates(providerConfig, 'anthropic'))
          .any((value) => _isZcodePlanEndpoint(value, officialPlanBaseUrls));
}

Iterable<String> _endpointCandidates(
    Map<String, dynamic> providerConfig, String format) sync* {
  final endpoints = providerConfig['endpoints'];
  if (endpoints is! Map) return;
  final normalized = format.trim().toLowerCase();
  final aliases = normalized.startsWith('anthropic')
      ? const ['anthropic-messages', 'anthropic']
      : const [
          'openai-compatible',
          'openai-chat-completions',
          'openai-responses',
          'openai'
        ];
  final values = <String>[];
  void add(dynamic value) {
    if (value is String) {
      values.add(value);
    } else if (value is Map) {
      for (final nested in value.values) {
        if (nested is String) values.add(nested);
      }
    }
  }

  for (final alias in aliases) {
    if (endpoints.containsKey(alias)) add(endpoints[alias]);
  }
  final paths = endpoints['paths'];
  if (paths is Map) {
    for (final alias in aliases) {
      if (paths.containsKey(alias)) add(paths[alias]);
    }
  }
  final base = endpoints['baseURL'];
  if (base is String && base.trim().isNotEmpty) {
    values.add(base);
    if (paths is Map) {
      for (final alias in aliases) {
        final path = paths[alias];
        if (path is String && path.trim().isNotEmpty) {
          final left = base.replaceFirst(RegExp(r'/+$'), '');
          final right = path.startsWith('/') ? path : '/$path';
          values.add('$left$right');
        }
      }
    }
  }
  yield* values;
}

bool _isZcodePlanEndpoint(String value, Iterable<String> officialBases) {
  final normalized =
      value.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  for (final base in officialBases) {
    final normalizedBase =
        base.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase();
    if (normalized == normalizedBase ||
        normalized.startsWith('$normalizedBase/')) {
      return true;
    }
  }
  return normalized.endsWith('/zcode-plan') ||
      normalized.endsWith('/zcode-plan/anthropic');
}

class _AttemptRecord {
  _AttemptRecord({
    required this.fingerprint,
    required this.token,
    required this.future,
    required this.providerId,
    required this.source,
    required this.modelId,
  });

  final String fingerprint;
  final int token;
  final Future<ModelConnectivityOutcome> future;
  final String providerId;
  final String source;
  final String modelId;
  ModelConnectivityStatus status = ModelConnectivityStatus.pending;
  ModelConnectivityOutcome? outcome;
}

/// Local, fake-channel-ready implementation of the official connectivity
/// action. One instance belongs to one device/workspace scope.
class ModelConnectivityController extends ChangeNotifier {
  ModelConnectivityController({
    required this.session,
    required this.scopeKey,
    this.dynamicHeadersResolver,
  }) : _captchaService = null {
    session.degraded.addListener(_onSourceChanged);
    session.recovered.addListener(_onSourceChanged);
  }

  /// Owns one CAPTCHA service for this device/workspace scope. The service is
  /// disposed together with the controller, and active challenge request ids
  /// are cancelled when an attempt is invalidated or the bridge changes.
  ModelConnectivityController.withCaptcha({
    required this.session,
    required this.scopeKey,
    required ModelCaptchaService captcha,
  })  : dynamicHeadersResolver = null,
        _captchaService = captcha {
    session.degraded.addListener(_onSourceChanged);
    session.recovered.addListener(_onSourceChanged);
  }

  final BridgeSession session;
  final String scopeKey;
  final ModelConnectivityDynamicHeadersResolver? dynamicHeadersResolver;
  final ModelCaptchaService? _captchaService;

  final Map<String, _AttemptRecord> _attempts = {};
  final Map<int, String> _captchaRequestIds = {};
  int _nextToken = 0;
  bool _disposed = false;

  static int _nextCaptchaRequestSequence = 0;

  String _key(String providerId, String modelId) =>
      '${providerId.trim()}::${modelId.trim()}';

  ModelConnectivityAttempt? attemptFor(String providerId, String modelId) {
    final record = _attempts[_key(providerId, modelId)];
    if (record == null) return null;
    return ModelConnectivityAttempt(
      providerId: record.providerId,
      source: record.source,
      modelId: record.modelId,
      status: record.status,
      outcome: record.outcome,
    );
  }

  bool isTesting(String providerId, String modelId) =>
      attemptFor(providerId, modelId)?.pending == true;

  ModelConnectivityOutcome? resultFor(String providerId, String modelId) =>
      attemptFor(providerId, modelId)?.outcome;

  /// Clears visible results immediately when a provider draft changes. Any
  /// in-flight operation loses its record, so its eventual response cannot
  /// project into a newer draft.
  void invalidateProvider(String providerId) {
    final prefix = '${providerId.trim()}::';
    final keys = _attempts.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    if (keys.isEmpty) return;
    for (final key in keys) {
      final record = _attempts[key];
      if (record != null) _cancelCaptchaToken(record.token);
      _attempts.remove(key);
    }
    _nextToken++;
    if (!_disposed) notifyListeners();
  }

  void invalidateModel(String providerId, String modelId) {
    final record = _attempts.remove(_key(providerId, modelId));
    final removed = record != null;
    if (!removed) return;
    _cancelCaptchaToken(record.token);
    _nextToken++;
    if (!_disposed) notifyListeners();
  }

  /// Alias matching the official operation name.
  Future<ModelConnectivityOutcome> testModelConnectivity({
    required ModelProviderEntry provider,
    required ModelEntry model,
    Map<String, dynamic>? draft,
    Map<String, dynamic>? readOnlyEndpoints,
  }) =>
      testModel(
        provider: provider,
        model: model,
        draft: draft,
        readOnlyEndpoints: readOnlyEndpoints,
      );

  Future<ModelConnectivityOutcome> testModel({
    required ModelProviderEntry provider,
    required ModelEntry model,
    Map<String, dynamic>? draft,
    Map<String, dynamic>? readOnlyEndpoints,
  }) {
    final modelId = model.id.trim();
    final key = _key(provider.id, modelId);
    final fingerprint = _fingerprint(
      provider: provider,
      modelRaw: model.raw,
      modelId: modelId,
      draft: draft,
      readOnlyEndpoints: readOnlyEndpoints,
    );
    final previous = _attempts[key];
    if (previous != null &&
        previous.fingerprint == fingerprint &&
        previous.status == ModelConnectivityStatus.pending) {
      return previous.future;
    }
    // A changed provider/source/draft invalidates the old visible result at
    // once. The old Future may finish, but its token cannot write this map.
    _attempts.remove(key);
    if (_disposed) {
      return Future.value(const ModelConnectivityOutcome(
        success: false,
        failureReason: 'controller disposed',
      ));
    }

    final token = ++_nextToken;
    final completer = Completer<ModelConnectivityOutcome>();
    _attempts[key] = _AttemptRecord(
      fingerprint: fingerprint,
      token: token,
      future: completer.future,
      providerId: provider.id,
      source: _source(provider, draft),
      modelId: modelId,
    );
    unawaited(_run(
      provider: provider,
      model: model,
      draft: draft,
      readOnlyEndpoints: readOnlyEndpoints,
      token: token,
    ).then((outcome) {
      final current = _attempts[key];
      if (!_disposed && current?.token == token) {
        current!.status = outcome.success
            ? ModelConnectivityStatus.success
            : ModelConnectivityStatus.failure;
        current.outcome = outcome;
        notifyListeners();
      }
      if (!completer.isCompleted) completer.complete(outcome);
    }, onError: (Object error, StackTrace stack) {
      // `_run` normally converts all failures to a redacted outcome. This
      // final guard keeps an unexpected local formatting failure retryable
      // without storing a provider payload or exception object.
      final outcome = const ModelConnectivityOutcome(
        success: false,
        failureReason: 'connectivity test failed',
      );
      final current = _attempts[key];
      if (!_disposed && current?.token == token) {
        current!.status = ModelConnectivityStatus.failure;
        current.outcome = outcome;
        notifyListeners();
      }
      if (!completer.isCompleted) completer.complete(outcome);
    }));
    notifyListeners();
    return completer.future;
  }

  Future<ModelConnectivityOutcome> _run({
    required ModelProviderEntry provider,
    required ModelEntry model,
    required Map<String, dynamic>? draft,
    required Map<String, dynamic>? readOnlyEndpoints,
    required int token,
  }) async {
    if (model.id.trim().isEmpty) {
      return const ModelConnectivityOutcome(
        success: false,
        failureReason: 'model id is required',
      );
    }
    final visible = <String, dynamic>{
      ...provider.raw,
      if (draft != null) ...draft,
    };
    final config = buildModelConnectivityPayload(
      provider: provider,
      modelId: model.id,
      draft: draft,
      readOnlyEndpoints: readOnlyEndpoints,
    );
    final providerConfig = (config['provider'] as Map).cast<String, dynamic>();
    // Gate from the final constructed provider config so read-only endpoint
    // overrides participate in the same official aut/vo -> iut decision.
    final planProvider = isZcodePlanProvider(provider, providerConfig);
    final apiKey = config['apiKey'] is String ? config['apiKey'] as String : '';
    final secrets = _secretValues(visible);
    Map<String, dynamic>? dynamicHeaders;
    try {
      if (planProvider) {
        final service = _captchaService;
        final resolver = dynamicHeadersResolver;
        if (service == null && resolver == null) {
          return const ModelConnectivityOutcome(
            success: false,
            failureReason: 'dynamic zcode-plan headers are required',
          );
        }
        if (service != null) {
          final requestId = _captchaRequestId(token);
          _captchaRequestIds[token] = requestId;
          try {
            dynamicHeaders = await service.resolveHeaders(
              providerId: provider.id,
              scopeKey: scopeKey,
              requestId: requestId,
            );
          } finally {
            if (_captchaRequestIds[token] == requestId) {
              _captchaRequestIds.remove(token);
            }
          }
        } else {
          dynamicHeaders = await resolver!(provider, providerConfig);
        }
        if (dynamicHeaders == null || dynamicHeaders.isEmpty) {
          return const ModelConnectivityOutcome(
            success: false,
            failureReason: 'dynamic zcode-plan headers are required',
          );
        }
        secrets.addAll(_stringValues(dynamicHeaders));
      } else if (apiKey.trim().isEmpty) {
        return const ModelConnectivityOutcome(
          success: false,
          failureReason: 'API key is required',
        );
      }

      final payload = buildModelConnectivityPayload(
        provider: provider,
        modelId: model.id,
        draft: draft,
        readOnlyEndpoints: readOnlyEndpoints,
        dynamicHeaders: dynamicHeaders,
      );
      if (_disposed ||
          !_isCurrent(provider, model, token, draft, readOnlyEndpoints)) {
        return const ModelConnectivityOutcome(
          success: false,
          failureReason: 'connectivity attempt superseded',
        );
      }
      final raw = await session.channels.call(
        Channels.modelProvider,
        'testModelConnectivity',
        [payload],
        timeout: const Duration(seconds: 30),
      );
      final outcome = parseModelConnectivityResponse(raw, secrets: secrets);
      return outcome;
    } catch (error) {
      final message = _redact('$error', secrets).trim();
      return ModelConnectivityOutcome(
        success: false,
        failureReason: message.isEmpty ? 'connectivity test failed' : message,
      );
    }
  }

  bool _isCurrent(
    ModelProviderEntry provider,
    ModelEntry model,
    int token,
    Map<String, dynamic>? draft,
    Map<String, dynamic>? readOnlyEndpoints,
  ) {
    final modelId = model.id.trim();
    final current = _attempts[_key(provider.id, modelId)];
    return current?.token == token &&
        current?.fingerprint ==
            _fingerprint(
              provider: provider,
              modelRaw: model.raw,
              modelId: modelId.trim(),
              draft: draft,
              readOnlyEndpoints: readOnlyEndpoints,
            );
  }

  String _fingerprint({
    required ModelProviderEntry provider,
    required Map<String, dynamic> modelRaw,
    required String modelId,
    required Map<String, dynamic>? draft,
    required Map<String, dynamic>? readOnlyEndpoints,
  }) {
    final value = <String, dynamic>{
      'provider': provider.raw,
      'providerId': provider.id,
      'source': provider.source,
      'model': modelId,
      'modelRaw': modelRaw,
      'draft': draft,
      'readOnlyEndpoints': readOnlyEndpoints,
    };
    final canonical = jsonEncode(_canonical(value));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  String _source(ModelProviderEntry provider, Map<String, dynamic>? draft) {
    final value = draft?['source'];
    return value is String ? value : provider.source;
  }

  void _onSourceChanged() {
    // A degraded/recovered bridge is a new transport source. In-flight calls
    // remain harmless because the token check rejects their late projection.
    for (final token in _captchaRequestIds.keys.toList(growable: false)) {
      _cancelCaptchaToken(token);
    }
    _captchaService?.invalidateConfig();
    _nextToken++;
    _attempts.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final token in _captchaRequestIds.keys.toList(growable: false)) {
      _cancelCaptchaToken(token);
    }
    _nextToken++;
    session.degraded.removeListener(_onSourceChanged);
    session.recovered.removeListener(_onSourceChanged);
    _attempts.clear();
    _captchaRequestIds.clear();
    _captchaService?.dispose();
    super.dispose();
  }

  String _captchaRequestId(int token) {
    _nextCaptchaRequestSequence++;
    return 'model-connectivity-captcha-$_nextCaptchaRequestSequence-$token';
  }

  void _cancelCaptchaToken(int token) {
    final requestId = _captchaRequestIds.remove(token);
    final service = _captchaService;
    if (requestId != null && service != null) {
      unawaited(service.cancel(requestId));
    }
  }
}

ModelConnectivityOutcome parseModelConnectivityResponse(
  Object? response, {
  Iterable<String> secrets = const [],
}) {
  final results = response is Map && response['results'] is List
      ? (response['results'] as List)
      : const <dynamic>[];
  final success =
      results.any((result) => result is Map && result['success'] == true);
  if (success) {
    return const ModelConnectivityOutcome(success: true);
  }
  final messages = <String>[];
  for (final result in results) {
    if (result is! Map) continue;
    final error = result['error'];
    final message = error is Map
        ? error['message']
        : error is String
            ? error
            : null;
    if (message == null) continue;
    final trimmed = _redact('$message', secrets).trim();
    if (trimmed.isNotEmpty && !messages.contains(trimmed)) {
      messages.add(trimmed);
    }
  }
  return ModelConnectivityOutcome(
    success: false,
    failureReason: messages.isEmpty ? null : messages.join('; '),
    noEndpointResult: results.isEmpty,
  );
}

Set<String> _secretValues(Map<String, dynamic> value) {
  final secrets = <String>{};
  final apiKey = value['apiKey'];
  if (apiKey is String && apiKey.isNotEmpty) secrets.add(apiKey);
  final headers = value['headers'];
  if (headers is Map) secrets.addAll(_stringValues(headers));
  return secrets;
}

Set<String> _stringValues(dynamic value) {
  final result = <String>{};
  if (value is Map) {
    for (final item in value.values) {
      result.addAll(_stringValues(item));
    }
  } else if (value is List) {
    for (final item in value) {
      result.addAll(_stringValues(item));
    }
  } else if (value is String && value.length >= 3) {
    result.add(value);
  }
  return result;
}

String _redact(String value, Iterable<String> secrets) {
  var redacted = value;
  for (final secret in secrets) {
    if (secret.isNotEmpty) redacted = redacted.replaceAll(secret, '[redacted]');
  }
  return redacted;
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return <String, dynamic>{
      for (final entry in entries) '${entry.key}': _canonical(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _canonical(item)];
  return value;
}
