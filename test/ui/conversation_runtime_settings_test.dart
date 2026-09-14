import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_settings.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';

void main() {
  test('reasoning and todo settings are view gates with official defaults', () {
    final hidden = RemoteSettingsSnapshot(
      messageStreamShowReasoning: false,
      messageStreamShowTodos: false,
    );
    final rows = <Map<String, dynamic>>[
      {'kind': 'reasoning', 'rowId': 1},
      {'kind': 'reasoning', 'rowId': 2},
      {'kind': 'toolCall', 'toolName': 'TodoWrite', 'rowId': 3},
      {'kind': 'assistantText', 'rowId': 4},
    ];
    final visible = runtimeVisibleAssistantRows(rows, hidden);
    expect(visible.map((row) => row['rowId']), [1, 4]);
    expect(rows, hasLength(4), reason: 'source conversation rows stay intact');
    expect(RemoteSettingsSnapshot().showReasoning, isTrue);
    expect(RemoteSettingsSnapshot().showTodos, isFalse);
  });

  test('tool grouping uses command classification rather than Bash name', () {
    expect(
        runtimeToolGroupingFamily({
          'kind': 'toolCall',
          'toolName': 'Bash',
          'input': {'command': 'ls -la'},
        }),
        'explore');
    expect(
        runtimeToolGroupingFamily({
          'kind': 'toolCall',
          'toolName': 'Bash',
          'input': {'command': 'npm test'},
        }),
        'terminal');
    expect(
        runtimeToolGroupingFamily({
          'kind': 'toolCall',
          'toolName': 'Edit',
          'input': {'file_path': 'lib/main.dart'},
        }),
        isNull);
    expect(
        runtimeToolGroupingFamily(
            {'kind': 'toolCall', 'toolName': 'Edit'},
            groupChanges: true),
        'changes');
  });
}
