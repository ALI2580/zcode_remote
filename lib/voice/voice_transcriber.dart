/// Platform-neutral offline transcription contract.
abstract class VoiceTranscriber {
  bool get isRecording => false;
  Future<bool> hasPermission() async => false;
  Future<void> start({void Function(String text)? onPartial}) async {}
  Future<String> stop() async => '';
  Future<void> cancel() async {}
  Future<void> dispose() async {}
}
