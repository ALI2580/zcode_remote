import 'voice_models.dart';
import 'voice_model_store_stub.dart';

Future<VoiceModelAvailability> voiceModelAvailability(
        VoiceModelStore store, VoiceModelInfo model) async =>
    VoiceModelAvailability.storageUnavailable;

Future<VoiceModelAvailability> voiceModelInputAvailability(
        VoiceModelStore store) async =>
    VoiceModelAvailability.storageUnavailable;
