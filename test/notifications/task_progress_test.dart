import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/conversation.dart';

const sourceA = WorkspaceTaskSource(
    deviceId: 'device-A', deviceLabel: 'A', workspaceKey: 'shared');
const sourceB = WorkspaceTaskSource(
    deviceId: 'device-B', deviceLabel: 'B', workspaceKey: 'shared');
SessionEntry entry(String phase,
        {String id = 'same-task',
        String? interaction,
        bool background = false}) =>
    SessionEntry({
      'sessionId': id,
      'title': '测试任务',
      'phase': phase,
      'hasBackgroundWork': background,
      if (interaction != null)
        'pendingInteraction': {'interactionId': interaction}
    });

void main() {
  test(
      'initial history and disappeared entries do not generate completion notices',
      () {
    final reducer = TaskProgressReducer();
    expect(reducer.update(sourceA, [entry('completed')]), isEmpty);
    reducer.update(sourceA, [entry('running')]);
    expect(reducer.update(sourceA, []), isEmpty);
  });
  test('same workspace and session ids on two devices stay independent', () {
    final reducer = TaskProgressReducer();
    reducer.update(sourceA, [entry('running')]);
    reducer.update(sourceB, [entry('running')]);
    expect(reducer.active, hasLength(2));
    final notices = reducer.update(sourceA, [entry('completedSuccess')]);
    expect(notices.single.target.deviceId, 'device-A');
    expect(reducer.active.single.target.deviceId, 'device-B');
    expect(reducer.update(sourceA, [entry('completedSuccess')]), isEmpty);
  });
  test('failure and cancellation are not reported as successful completion',
      () {
    final reducer = TaskProgressReducer();
    reducer.update(sourceA, [entry('running')]);
    expect(reducer.update(sourceA, [entry('failed')]).single.title, '任务失败');
    reducer.update(sourceA, [entry('running')]);
    expect(
        reducer.update(sourceA, [entry('completedInterrupted')]).single.title,
        '任务已停止');
  });
  test('attention is deduplicated by device, workspace, task and interaction',
      () {
    final reducer = TaskProgressReducer();
    expect(reducer.update(sourceA, [entry('running', interaction: 'q')]),
        hasLength(1));
    expect(
        reducer.update(sourceA, [entry('running', interaction: 'q')]), isEmpty);
    expect(reducer.update(sourceB, [entry('running', interaction: 'q')]),
        hasLength(1));
    expect(reducer.active.every((task) => task.needsAttention), isTrue);
  });
  test('background work keeps progress active until it actually finishes', () {
    final reducer = TaskProgressReducer();
    reducer.update(sourceA, [entry('completed', background: true)]);
    expect(reducer.active, hasLength(1));
    expect(reducer.update(sourceA, [entry('completed')]).single.title, '任务完成');
    expect(reducer.active, isEmpty);
  });
  test('notification target validates all scopes and excludes URL credentials',
      () {
    final target = sourceA.target(entry('running'));
    expect(TaskTarget.parse(target.toJson())?.key, target.key);
    expect(target.toJson().containsKey('url'), isFalse);
    expect(TaskTarget.parse({'sessionId': 'only-session'}), isNull);
    expect(TaskTarget.parse('invalid json'), isNull);
  });
}
