/// Stable failure categories used by the voice controller and composer UI.
enum VoiceFailureKind {
  modelNotDownloaded,
  modelNotEnabled,
  modelUnavailable,
  modelCorrupt,
  storageUnavailable,
  permissionDenied,
  recognizerUnavailable,
  cancelled,
  busy,
  sessionNotReady,
  modelDownloadFailed,
  unknown,
}

String? voiceFailureMessage(VoiceFailureKind? kind, {required bool english}) {
  if (kind == null) return null;
  return switch (kind) {
    VoiceFailureKind.modelNotDownloaded => english
        ? 'No offline voice model is downloaded. Open the model manager to download one.'
        : '尚未下载离线语音模型，请打开模型管理下载。',
    VoiceFailureKind.modelNotEnabled => english
        ? 'A voice model is downloaded but not enabled. Open the model manager to enable it.'
        : '语音模型已下载但尚未启用，请打开模型管理启用。',
    VoiceFailureKind.modelUnavailable => english
        ? 'Voice input is unavailable. Check the model manager.'
        : '语音输入不可用，请检查模型管理。',
    VoiceFailureKind.modelCorrupt => english
        ? 'The voice model is damaged. Open the model manager to download it again.'
        : '语音模型已损坏，请打开模型管理重新下载。',
    VoiceFailureKind.storageUnavailable => english
        ? 'Voice model storage is unavailable. Check storage permission and retry.'
        : '语音模型存储不可用，请检查存储权限后重试。',
    VoiceFailureKind.permissionDenied => english
        ? 'Microphone permission is required. Allow it and retry.'
        : '需要麦克风权限，请允许权限后重试。',
    VoiceFailureKind.recognizerUnavailable => english
        ? 'Voice recognition is unavailable. Check the enabled model and retry.'
        : '语音识别不可用，请检查已启用模型后重试。',
    VoiceFailureKind.cancelled =>
      english ? 'Voice input was cancelled.' : '语音输入已取消。',
    VoiceFailureKind.busy =>
      english ? 'Voice recognition is already in progress.' : '语音识别正在进行中。',
    VoiceFailureKind.sessionNotReady => english
        ? 'The current session is not ready for voice input yet.'
        : '当前会话尚未准备好语音输入。',
    VoiceFailureKind.modelDownloadFailed => english
        ? 'The voice model operation failed. Try again.'
        : '语音模型操作失败，请重试。',
    VoiceFailureKind.unknown => null,
  };
}

class VoiceTranscriberException implements Exception {
  const VoiceTranscriberException(
    this.kind,
    this.message, {
    this.modelId,
  });

  final VoiceFailureKind kind;
  final String message;
  final String? modelId;

  @override
  String toString() => message;
}

class VoiceModelStoreException implements Exception {
  const VoiceModelStoreException(this.kind, this.message);

  final VoiceFailureKind kind;
  final String message;

  @override
  String toString() => message;
}
