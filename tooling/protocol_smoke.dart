import 'dart:convert';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/device_info.dart';
import 'package:zcode_remote/protocol/plan_reset.dart';

/// Run with `dart run`, not a Flutter engine. Importing ConversationTransport
/// compiles the complete relay/bridge stack and catches widget dependencies.
void main() {
  final state = ConversationState();
  var notifications = 0;
  state.addListener(() => notifications++);
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        'revision': 1,
        'rows': [],
        'config': {'model': 'synthetic'}
      }
    }
  }, onGap: () => throw StateError('unexpected gap'));
  if (!state.ready || notifications != 1) throw StateError('projection failed');
  state.dispose();
  final reset = PlanResetStatus.parse({
    'availableFiveHourResets': [],
    'availableWeekResets': [],
    'hasUnreadHistory': false,
  });
  if (reset.available(PlanResetType.week, 1).isNotEmpty) {
    throw StateError('reset projection failed');
  }
  // ignore: avoid_print
  print(jsonEncode({
    'protocol': 'pure-dart',
    'platform': zemotePlatformName(),
    'projection': 'passed'
  }));
}
