/// Download pipeline phase shown in the model manager (U25). `extracting`
/// and `verifying` prove that 100% downloaded is not the same as usable.
enum VoiceDownloadPhase { downloading, extracting, verifying }

class VoiceDownloadState {
  const VoiceDownloadState(this.phase, {this.received = 0, this.total});
  final VoiceDownloadPhase phase;

  /// Bytes received so far; meaningful in every phase for feedback.
  final int received;

  /// Total archive bytes when the response carries a Content-Length.
  /// Unknown totals must never fabricate a percentage.
  final int? total;

  /// Null when the total size is unknown: the UI then shows received bytes
  /// and an indeterminate bar instead of a stuck 0%.
  double? get percent =>
      (total == null || total! <= 0) ? null : (received / total!).clamp(0.0, 1.0);
}
