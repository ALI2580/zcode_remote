import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/chat_page.dart';

void main() {
  group('emptyGreeting (官方 chat.empty.greeting)', () {
    test('时段问候覆盖全天', () {
      expect(emptyGreeting(DateTime(2026, 1, 1, 6)), '早上好呀，新的一天开始啦');
      expect(emptyGreeting(DateTime(2026, 1, 1, 9)), '上午好呀，有什么想让我帮忙的吗');
      expect(emptyGreeting(DateTime(2026, 1, 1, 12)), '中午好呀，要不要先休息一下');
      expect(emptyGreeting(DateTime(2026, 1, 1, 15)), '下午好呀，接下来交给我吧');
      expect(emptyGreeting(DateTime(2026, 1, 1, 20)), '晚上好呀，今天辛苦啦');
      expect(emptyGreeting(DateTime(2026, 1, 1, 2)), '夜深啦，别忘了照顾好自己哦');
    });
  });

  group('formatTurnDuration (chat.history.duration.*)', () {
    test('秒/分/时/天 compact，零尾单位丢弃', () {
      expect(formatTurnDuration(0), '0秒');
      expect(formatTurnDuration(3 * 1000), '3秒');
      expect(formatTurnDuration(62 * 1000), '1分2秒');
      expect(formatTurnDuration(2 * 3600 * 1000 + 5 * 60 * 1000), '2时5分');
      expect(formatTurnDuration(1 * 86400 * 1000 + 30 * 1000), '1天30秒');
    });
  });

  group('turnDurationMs (bundle BX)', () {
    test('activeMs 优先', () {
      expect(
        turnDurationMs({'activeMs': 5000, 'startedAt': 1000, 'endedAt': 2000},
            running: false),
        5000,
      );
    });

    test('否则 endedAt-startedAt', () {
      expect(
        turnDurationMs({'startedAt': 1000, 'endedAt': 2000}, running: false),
        1000,
      );
    });

    test('运行中用 now-startedAt', () {
      final row = {'startedAt': DateTime.now().millisecondsSinceEpoch - 8000};
      final ms = turnDurationMs(row, running: true);
      expect(ms, greaterThanOrEqualTo(7900));
      expect(ms, lessThanOrEqualTo(8500));
    });
  });

  group('turnWorkLabel (chat.history.*)', () {
    test('running 显示工作中 + 时长', () {
      expect(turnWorkLabel(state: 'running', durationMs: 62000), '工作中 1分2秒');
      expect(turnWorkLabel(state: 'running', durationMs: null), '工作中');
    });

    test('interrupted/failed 显示已停止', () {
      expect(
          turnWorkLabel(state: 'completedInterrupted', durationMs: 100), '已停止');
      expect(turnWorkLabel(state: 'failed', durationMs: 100), '已停止');
    });

    test('completed 显示已工作 + 时长（无时长则已处理）', () {
      expect(turnWorkLabel(state: 'completed', durationMs: 90000), '已工作 1分30秒');
      expect(turnWorkLabel(state: 'completed', durationMs: null), '已处理');
    });
  });

  group('turnDefaultOpen (§1 官方默认展开逻辑)', () {
    test('最后 turn 运行中 → 展开', () {
      expect(
        turnDefaultOpen(
            isLastTurn: true,
            running: true,
            singleTurn: false,
            hasAssistantText: true,
            hasWorkRows: true),
        isTrue,
      );
    });

    test('历史 turn 完成 → 收起', () {
      expect(
        turnDefaultOpen(
            isLastTurn: false,
            running: false,
            singleTurn: false,
            hasAssistantText: true,
            hasWorkRows: true),
        isFalse,
      );
    });

    test('仅一个 turn、无正文、有工作行 → 展开', () {
      expect(
        turnDefaultOpen(
            isLastTurn: true,
            running: false,
            singleTurn: true,
            hasAssistantText: false,
            hasWorkRows: true),
        isTrue,
      );
    });
  });
}
