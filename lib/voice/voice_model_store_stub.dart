import 'voice_download_state.dart';
import 'voice_models.dart';

/// Stub voice model store (web/unsupported platforms).
class VoiceModelStore {
  VoiceModelStore();
  static final VoiceModelStore instance = VoiceModelStore();
  final Map<String, double> progress = const {};
  final Map<String, VoiceDownloadState> downloadStates = const {};

  Future<bool> isDownloaded(VoiceModelInfo model) async => false;

  Future<String?> enabledModelId() async => null;

  Future<void> setEnabled(VoiceModelInfo model) async =>
      throw UnimplementedError();

  Future<void> disable(VoiceModelInfo model) async =>
      throw UnimplementedError();

  Future<void> download(VoiceModelInfo model) async =>
      throw UnimplementedError();

  void cancelDownload(VoiceModelInfo model) {}

  Future<void> delete(VoiceModelInfo model) async => throw UnimplementedError();
}
