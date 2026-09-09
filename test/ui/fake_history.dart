import 'package:zcode_remote/protocol/conversation.dart';
import 'fake_workspace.dart';

List<Map<String, dynamic>> readingRows(int first, int last) => [
      for (var i = first; i <= last; i++)
        {
          'rowId': i,
          'kind': 'userInput',
          'text':
              'Reading message $i\n${List.filled(i % 5 + 1, '这是用于分页和阅读恢复的合成消息。不同段落长度会改变行高，旋转后仍应恢复同一位置。').join('\n')}'
        }
    ];

ConversationState readingState(int first, int last) => ConversationState()
  ..applyFrame({
    'toSeq': 20,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        ...composerSnapshotFixture,
        'logEpoch': 'reading-fixture',
        'rows': {
          'window': readingRows(first, last),
          'firstRowId': 1,
          'totalCount': last
        }
      }
    }
  }, onGap: () {});

Map<String, dynamic> readingPage(int before) {
  final first = (before - 200).clamp(1, before);
  return {
    'rows': readingRows(first, before - 1),
    'atSeq': 20,
    'atLogEpoch': 'reading-fixture',
    'hasMore': first > 1
  };
}
