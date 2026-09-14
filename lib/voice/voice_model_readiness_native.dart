import 'dart:io';

import 'voice_model_store_native.dart';
import 'voice_models.dart';

/// Reads the local model state without downloading or changing preferences.
/// The fallback path keeps injected test stores and alternate stores usable.
Future<VoiceModelAvailability> voiceModelAvailability(
    VoiceModelStore store, VoiceModelInfo model) async {
  try {
    final downloaded = await store.isDownloaded(model);
    if (store.runtimeType != VoiceModelStore) {
      if (!downloaded) return VoiceModelAvailability.notDownloaded;
      final enabledId = await store.enabledModelId();
      return enabledId == model.id
          ? VoiceModelAvailability.enabled
          : VoiceModelAvailability.downloaded;
    }
    if (!downloaded) {
      try {
        final directory = await store.directory(model);
        if (await directory.exists()) return VoiceModelAvailability.corrupt;
      } on FileSystemException {
        return VoiceModelAvailability.storageUnavailable;
      }
      return VoiceModelAvailability.notDownloaded;
    }
    final configuredId = await configuredVoiceModelId();
    if (configuredId != model.id) return VoiceModelAvailability.downloaded;
    await verifyVoiceModelFiles(store, model);
    return VoiceModelAvailability.enabled;
  } on FileSystemException {
    return VoiceModelAvailability.storageUnavailable;
  } catch (_) {
    // An enabled model whose manifest or content fails verification is
    // reported as corrupt. A test/injected store may only expose a generic
    // error; that remains actionable as a corrupt local model.
    return VoiceModelAvailability.corrupt;
  }
}

Future<VoiceModelAvailability> voiceModelInputAvailability(
    VoiceModelStore store) async {
  if (store.runtimeType != VoiceModelStore) {
    return _scanInputAvailability(store);
  }
  final configured = await configuredVoiceModelId();
  if (configured != null &&
      voiceModels.any((model) => model.id == configured)) {
    return voiceModelAvailability(store, voiceModelById(configured));
  }
  return _scanInputAvailability(store);
}

Future<VoiceModelAvailability> _scanInputAvailability(
    VoiceModelStore store) async {
  var sawCorrupt = false;
  for (final model in voiceModels) {
    final state = await voiceModelAvailability(store, model);
    if (state == VoiceModelAvailability.enabled) return state;
    if (state == VoiceModelAvailability.downloaded) {
      return state;
    }
    if (state == VoiceModelAvailability.corrupt) sawCorrupt = true;
    if (state == VoiceModelAvailability.storageUnavailable) return state;
  }
  return sawCorrupt
      ? VoiceModelAvailability.corrupt
      : VoiceModelAvailability.notDownloaded;
}
