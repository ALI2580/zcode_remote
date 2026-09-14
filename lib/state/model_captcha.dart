import 'dart:async';

import 'package:flutter/services.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

/// The SDK URL is frozen by the official web bundle. The native adapter only
/// loads this script inside its temporary, restricted challenge WebView.
const modelCaptchaSdkScriptUrl =
    'https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';

const modelCaptchaConfigCacheDuration = Duration(seconds: 60);
const modelCaptchaTimeout = Duration(seconds: 120);

/// A validated, non-secret projection of `coding-plan-subscription`'s
/// `getCaptchaConfig()` response.
class ModelCaptchaConfig {
  const ModelCaptchaConfig({
    required this.enabled,
    required this.region,
    required this.prefix,
    required this.sceneId,
  });

  factory ModelCaptchaConfig.fromRaw(Object? value) {
    if (value is ModelCaptchaConfig) return value;
    if (value is! Map) {
      return const ModelCaptchaConfig(
        enabled: true,
        region: '',
        prefix: '',
        sceneId: '',
      );
    }
    return ModelCaptchaConfig(
      enabled: value['enabled'] != false,
      region: _string(value['region']),
      prefix: _string(value['prefix']),
      sceneId: _string(value['sceneId']),
    );
  }

  final bool enabled;
  final String region;
  final String prefix;
  final String sceneId;

  bool get usable =>
      enabled &&
      region.trim().isNotEmpty &&
      prefix.trim().isNotEmpty &&
      sceneId.trim().isNotEmpty;

  Map<String, dynamic> get safeMap => {
        'enabled': enabled,
        'region': region,
        'prefix': prefix,
        'sceneId': sceneId,
      };

  @override
  bool operator ==(Object other) =>
      other is ModelCaptchaConfig &&
      other.enabled == enabled &&
      other.region == region &&
      other.prefix == prefix &&
      other.sceneId == sceneId;

  @override
  int get hashCode => Object.hash(enabled, region, prefix, sceneId);
}

String _string(Object? value) => value is String ? value.trim() : '';

/// The only values allowed across the native boundary. In particular, no
/// provider configuration, API key, sid, hash, or endpoint is included.
class ModelCaptchaChallengeRequest {
  const ModelCaptchaChallengeRequest({
    required this.region,
    required this.prefix,
    required this.sceneId,
    required this.language,
    required this.requestId,
  });

  final String region;
  final String prefix;
  final String sceneId;
  final String language;
  final String requestId;

  Map<String, String> get platformArguments => {
        'region': region,
        'prefix': prefix,
        'sceneId': sceneId,
        'language': language,
        'requestId': requestId,
      };
}

abstract class ModelCaptchaChallengeAdapter {
  const ModelCaptchaChallengeAdapter();

  /// Resolves only a string returned by the SDK success callback.
  Future<String?> verify(ModelCaptchaChallengeRequest request);

  /// Cancels only [requestId]. Implementations should release the temporary
  /// WebView and complete its pending platform result.
  Future<void> cancel(String requestId);

  void dispose() {}
}

/// MethodChannel adapter used by Android. A missing plugin is surfaced as a
/// failure by [ModelCaptchaService]; it never silently bypasses verification.
class MethodChannelModelCaptchaChallengeAdapter
    extends ModelCaptchaChallengeAdapter {
  MethodChannelModelCaptchaChallengeAdapter({MethodChannel? channel})
      : channel = channel ?? const MethodChannel('zcode_remote/model-captcha');

  final MethodChannel channel;

  @override
  Future<String?> verify(ModelCaptchaChallengeRequest request) async {
    final value = await channel.invokeMethod<Object?>(
      'verify',
      request.platformArguments,
    );
    // Native code must forward the SDK success callback string directly. A
    // map or arbitrary value is not accepted as a verification token.
    if (value is! String || value.trim().isEmpty) {
      throw const ModelCaptchaException(
        code: 'captcha_sdk_invalid_result',
        message: 'CAPTCHA SDK returned no verification parameter',
      );
    }
    return value.trim();
  }

  @override
  Future<void> cancel(String requestId) async {
    await channel.invokeMethod<void>('cancel', {'requestId': requestId});
  }
}

class ModelCaptchaException implements Exception {
  const ModelCaptchaException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

typedef ModelCaptchaConfigLoader = FutureOr<Object?> Function();
typedef ModelCaptchaClock = DateTime Function();
typedef ModelCaptchaLanguageProvider = String Function();

class _CaptchaRequest {
  _CaptchaRequest(this.id);

  final String id;
  final cancelledSignal = Completer<void>();
  bool cancelled = false;
  bool started = false;
  bool completed = false;
}

/// A process-wide FIFO queue. The official bundle serializes all zcode-plan
/// challenges globally, even when multiple model editor scopes are visible.
class _GlobalCaptchaQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> add<T>(Future<T> Function() operation) {
    final previous = _tail;
    final result = Completer<T>();
    _tail = () async {
      // A failed predecessor must not strand later challenges.
      try {
        await previous;
      } catch (_) {}
      try {
        result.complete(await operation());
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    }();
    return result.future;
  }
}

final _globalCaptchaQueue = _GlobalCaptchaQueue();
int _captchaRequestSequence = 0;

/// Local implementation of the official zcode-plan CAPTCHA preflight.
///
/// One instance should be associated with one bridge/device scope. The queue
/// is global, while cancellation and disposal are scoped to this instance and
/// request id. Configuration caching is instance-local so it cannot cross a
/// bridge/source boundary.
class ModelCaptchaService {
  ModelCaptchaService({
    required ModelCaptchaConfigLoader configLoader,
    required ModelCaptchaChallengeAdapter challengeAdapter,
    String language = 'en',
    ModelCaptchaLanguageProvider? languageProvider,
    ModelCaptchaClock? clock,
    Duration configCacheDuration = modelCaptchaConfigCacheDuration,
    Duration challengeTimeout = modelCaptchaTimeout,
  })  : _configLoader = configLoader,
        _challengeAdapter = challengeAdapter,
        _languageProvider = languageProvider ?? (() => language),
        _clock = clock ?? DateTime.now,
        _configCacheDuration = configCacheDuration,
        _challengeTimeout = challengeTimeout;

  factory ModelCaptchaService.fromSession({
    required BridgeSession session,
    ModelCaptchaChallengeAdapter? challengeAdapter,
    String language = 'en',
    ModelCaptchaLanguageProvider? languageProvider,
    ModelCaptchaClock? clock,
    Duration configCacheDuration = modelCaptchaConfigCacheDuration,
    Duration challengeTimeout = modelCaptchaTimeout,
  }) {
    return ModelCaptchaService(
      configLoader: () => session.channels.call(
        Channels.codingPlanSubscription,
        'getCaptchaConfig',
        const <Object?>[],
      ),
      challengeAdapter:
          challengeAdapter ?? MethodChannelModelCaptchaChallengeAdapter(),
      language: language,
      languageProvider: languageProvider,
      clock: clock,
      configCacheDuration: configCacheDuration,
      challengeTimeout: challengeTimeout,
    );
  }

  final ModelCaptchaConfigLoader _configLoader;
  final ModelCaptchaChallengeAdapter _challengeAdapter;
  final ModelCaptchaLanguageProvider _languageProvider;
  final ModelCaptchaClock _clock;
  final Duration _configCacheDuration;
  final Duration _challengeTimeout;
  final Map<String, _CaptchaRequest> _requests = {};
  final Map<String, String> _lastParamByProvider = {};

  ModelCaptchaConfig? _cachedConfig;
  DateTime? _cachedAt;
  Future<ModelCaptchaConfig?>? _configFuture;
  int _configGeneration = 0;
  bool _disposed = false;

  /// Calls `getCaptchaConfig` with no arguments, caches a successful or null
  /// result for 60 seconds, and shares concurrent reads.
  Future<ModelCaptchaConfig?> getCaptchaConfig() {
    if (_disposed) {
      return Future.error(const ModelCaptchaException(
        code: 'captcha_disposed',
        message: 'CAPTCHA service is disposed',
      ));
    }
    final cachedAt = _cachedAt;
    if (cachedAt != null &&
        _clock().difference(cachedAt) < _configCacheDuration) {
      return Future<ModelCaptchaConfig?>.value(_cachedConfig);
    }
    final current = _configFuture;
    if (current != null) return current;
    final generation = _configGeneration;
    final loaded = Future<Object?>.sync(_configLoader)
        .then<ModelCaptchaConfig?>((raw) => ModelCaptchaConfig.fromRaw(raw));
    final future = loaded.then((config) {
      if (!_disposed && generation == _configGeneration) {
        _cachedConfig = config;
        _cachedAt = _clock();
      }
      return config;
    }, onError: (Object error, StackTrace stack) {
      // The official zQ catches a transient getCaptchaConfig failure and
      // returns null, but writes PQ only after a successful await. A retry
      // must therefore issue a fresh RPC instead of reusing failure-as-null.
      return null;
    });
    _configFuture = future;
    future.whenComplete(() {
      if (identical(_configFuture, future)) _configFuture = null;
    });
    return future;
  }

  /// Invalidates the local config cache after a source/account change.
  void invalidateConfig() {
    _configGeneration++;
    _configFuture = null;
    _cachedConfig = null;
    _cachedAt = null;
  }

  /// Returns fresh dynamic headers for one plan connectivity request.
  ///
  /// Every invocation runs a new challenge and rejects a repeated
  /// `certifyId`/verification parameter so stale F008 values cannot be sent.
  Future<Map<String, dynamic>> resolveHeaders({
    required String providerId,
    String? scopeKey,
    String? requestId,
  }) async {
    if (_disposed) {
      throw const ModelCaptchaException(
        code: 'captcha_disposed',
        message: 'CAPTCHA service is disposed',
      );
    }

    final id = _nextRequestId(requestId);
    final request = _CaptchaRequest(id);
    if (_requests.containsKey(id)) {
      throw const ModelCaptchaException(
        code: 'captcha_duplicate_request',
        message: 'CAPTCHA request id is already active',
      );
    }
    _requests[id] = request;
    try {
      final config = await Future.any<ModelCaptchaConfig?>([
        getCaptchaConfig(),
        request.cancelledSignal.future.then<ModelCaptchaConfig?>((_) {
          throw const ModelCaptchaException(
            code: 'captcha_cancelled',
            message: 'CAPTCHA verification was cancelled',
          );
        }),
      ]);
      if (config == null) {
        throw const ModelCaptchaException(
          code: 'captcha_config_unavailable',
          message: 'CAPTCHA configuration is unavailable',
        );
      }
      if (!config.enabled) {
        throw const ModelCaptchaException(
          code: 'captcha_disabled',
          message: 'CAPTCHA verification is disabled',
        );
      }
      if (!config.usable) {
        throw const ModelCaptchaException(
          code: 'captcha_config_incomplete',
          message: 'CAPTCHA configuration is incomplete',
        );
      }
      if (_disposed || request.cancelled) {
        throw const ModelCaptchaException(
          code: 'captcha_cancelled',
          message: 'CAPTCHA verification was cancelled',
        );
      }
      final value = await _globalCaptchaQueue.add(() async {
        if (_disposed || request.cancelled) {
          throw const ModelCaptchaException(
            code: 'captcha_cancelled',
            message: 'CAPTCHA verification was cancelled',
          );
        }
        request.started = true;
        final challenge = ModelCaptchaChallengeRequest(
          region: config.region,
          prefix: config.prefix,
          sceneId: config.sceneId,
          language: _normalizeLanguage(_languageProvider()),
          requestId: id,
        );
        try {
          final result = await Future.any<String?>([
            _challengeAdapter.verify(challenge).timeout(_challengeTimeout),
            request.cancelledSignal.future.then<String?>((_) {
              throw const ModelCaptchaException(
                code: 'captcha_cancelled',
                message: 'CAPTCHA verification was cancelled',
              );
            }),
          ]);
          if (_disposed || request.cancelled) {
            throw const ModelCaptchaException(
              code: 'captcha_cancelled',
              message: 'CAPTCHA verification was cancelled',
            );
          }
          if (result == null || result.trim().isEmpty) {
            throw const ModelCaptchaException(
              code: 'captcha_sdk_invalid_result',
              message: 'CAPTCHA SDK returned no verification parameter',
            );
          }
          final param = result.trim();
          if (param == 'F008') {
            throw const ModelCaptchaException(
              code: 'captcha_duplicate',
              message: 'CAPTCHA returned a duplicate verification parameter',
            );
          }
          final providerKey = providerId.trim();
          final previous = _lastParamByProvider[providerKey];
          if (previous == param) {
            throw const ModelCaptchaException(
              code: 'captcha_duplicate',
              message: 'CAPTCHA returned a duplicate verification parameter',
            );
          }
          _lastParamByProvider[providerKey] = param;
          return buildModelCaptchaHeaders(
            verificationParam: param,
            region: config.region,
          );
        } on TimeoutException {
          await _cancelAdapter(request);
          throw const ModelCaptchaException(
            code: 'captcha_timeout',
            message: 'CAPTCHA verification timed out',
          );
        } on ModelCaptchaException {
          rethrow;
        } catch (error) {
          throw ModelCaptchaException(
            code: 'captcha_sdk_failed',
            message: _safeError(error),
          );
        }
      });
      return value;
    } finally {
      request.completed = true;
      _requests.remove(id);
    }
  }

  /// Cancels only this service's request. A queued request never starts; an
  /// active request asks the adapter to close its own native challenge.
  Future<void> cancel(String requestId) async {
    final request = _requests[requestId];
    if (request == null) return;
    request.cancelled = true;
    if (!request.cancelledSignal.isCompleted) {
      request.cancelledSignal.complete();
    }
    if (request.started && !request.completed) {
      await _cancelAdapter(request);
    }
  }

  Future<void> _cancelAdapter(_CaptchaRequest request) async {
    try {
      await _challengeAdapter.cancel(request.id);
    } catch (_) {
      // The original cancellation/timeout remains the visible outcome.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _requests.values.toList(growable: false);
    for (final request in pending) {
      request.cancelled = true;
      if (!request.cancelledSignal.isCompleted) {
        request.cancelledSignal.complete();
      }
      if (request.started && !request.completed) {
        unawaited(_cancelAdapter(request));
      }
    }
    _requests.clear();
    _challengeAdapter.dispose();
    _configGeneration++;
    _configFuture = null;
    _cachedConfig = null;
    _cachedAt = null;
    _lastParamByProvider.clear();
  }

  String _nextRequestId(String? requested) {
    final value = requested?.trim();
    if (value != null && value.isNotEmpty) return value;
    _captchaRequestSequence++;
    return 'model-captcha-$_captchaRequestSequence';
  }
}

String _normalizeLanguage(String value) =>
    value.trim().toLowerCase().startsWith('zh') ? 'cn' : 'en';

String _safeError(Object error) {
  if (error is PlatformException) {
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : 'CAPTCHA platform is unavailable';
  }
  if (error is MissingPluginException) return 'CAPTCHA platform is unavailable';
  final text = '$error'.trim();
  return text.isEmpty ? 'CAPTCHA verification failed' : text;
}

Map<String, dynamic> buildModelCaptchaHeaders({
  required String verificationParam,
  required String region,
}) {
  final headers = <String, dynamic>{
    'X-Aliyun-Captcha-Verify-Param': verificationParam,
  };
  if (region.trim().isNotEmpty) {
    headers['X-Aliyun-Captcha-Verify-Region'] = region.trim();
  }
  return headers;
}
