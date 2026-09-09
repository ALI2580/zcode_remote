import 'recovery_collections.dart';

/// Client-only reading state, scoped by device/workspace/conversation.
class ConversationViewState {
  void Function()? onChanged;
  bool _following = true;
  double _pixels = 0, _anchorOffset = 0;
  String? _anchor;
  String? _logEpoch;
  String? get logEpoch => _logEpoch;
  set logEpoch(String? value) {
    if (_logEpoch == value) return;
    _logEpoch = value;
    onChanged?.call();
  }

  late final expandedTurns = RecoveryMap<int, bool>(() => onChanged?.call());
  bool get following => _following;
  set following(bool value) {
    if (_following == value) return;
    _following = value;
    onChanged?.call();
  }

  double get pixels => _pixels;
  set pixels(double value) {
    if (_pixels == value || !value.isFinite) return;
    _pixels = value;
    if (!following) onChanged?.call();
  }

  String? get anchor => _anchor;
  set anchor(String? value) {
    if (_anchor == value) return;
    _anchor = value;
    if (!following) onChanged?.call();
  }

  double get anchorOffset => _anchorOffset;
  set anchorOffset(double value) {
    if (_anchorOffset == value || !value.isFinite) return;
    _anchorOffset = value;
    if (!following) onChanged?.call();
  }

  Map<String, dynamic> toJson() => {
        'following': following,
        if (logEpoch != null) 'logEpoch': logEpoch,
        if (!following) ...{
          'pixels': pixels,
          'anchor': anchor,
          'anchorOffset': anchorOffset
        },
        'expandedTurns': {
          for (final entry in expandedTurns.entries) '${entry.key}': entry.value
        },
      };
  static ConversationViewState fromJson(Map raw) {
    final state = ConversationViewState();
    if (raw['logEpoch'] case final String v) state.logEpoch = v;
    state.following = raw['following'] != false;
    if (raw['pixels'] case final num v when v.isFinite && v >= 0) {
      state.pixels = v.toDouble();
    }
    if (raw['anchor'] case final String v) state.anchor = v;
    if (raw['anchorOffset'] case final num v when v.isFinite) {
      state.anchorOffset = v.toDouble();
    }
    if (raw['expandedTurns'] case final Map entries) {
      for (final entry in entries.entries) {
        final key = int.tryParse('${entry.key}');
        if (key != null && entry.value is bool) {
          state.expandedTurns[key] = entry.value;
        }
      }
    }
    return state;
  }
}
