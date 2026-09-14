import 'package:flutter/foundation.dart';

/// Change notifier for voice model store updates.
class VoiceModelEvents extends ChangeNotifier {
  VoiceModelEvents._();
  static final VoiceModelEvents _instance = VoiceModelEvents._();
  static VoiceModelEvents get instance => _instance;
  static void notifyChanged() => _instance.notifyListeners();
}
