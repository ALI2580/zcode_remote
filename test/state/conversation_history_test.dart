import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/conversation_history.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import '../ui/fake_workspace.dart';

List<Map<String, dynamic>> rows(int first, int last) => [
      for (var i = first; i <= last; i++)
        {'rowId': i, 'kind': 'userInput', 'text': 'Row $i'}
    ];

void snapshot(ConversationState state, String epoch, int first, int last) {
  state.applyFrame({
    'toSeq': 20,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        'logEpoch': epoch,
        'rows': {
          'window': rows(first, last),
          'firstRowId': 1,
          'totalCount': last
        }
      }
    }
  }, onGap: () => fail('Unexpected gap'));
}

Map<String, dynamic> page(String epoch, int first, int last,
        {bool more = true}) =>
    {
      'rows': rows(first, last),
      'atLogEpoch': epoch,
      'atSeq': 10,
      'hasMore': more
    };

void main() {
  test('reading recovery pages only to its saved row, with no commands',
      () async {
    final transport = FakeBridge().conversationTransport;
    final state = ConversationState();
    snapshot(state, 'epoch', 801, 860);
    final view = ConversationViewState()
      ..following = false
      ..anchor = '450'
      ..anchorOffset = -15
      ..logEpoch = 'epoch';
    final history = ConversationHistory(
        transport: transport, sessionId: 'task-A', state: state, view: view);
    transport.historyHandler =
        (id, before, limit) async => page('epoch', before! - 200, before - 1);
    await history.restoreReading();
    expect(transport.historyRequests.map((r) => r.beforeRowId), [801, 601]);
    expect(
        transport.historyRequests
            .every((r) => r.limit == 200 && r.sessionId == 'task-A'),
        isTrue);
    expect(state.oldestRowId, 401);
    expect(view.anchor, '450');
    expect(view.anchorOffset, -15);
    expect(view.following, isFalse);
    expect(history.blocksViewport, isFalse);
    expect(state.seq, 20);
    expect(transport.commands, isEmpty);
    history.dispose();
  });

  test(
      'same-ID devices keep separate pages and concurrent reads share a request',
      () async {
    final a = FakeBridge().conversationTransport,
        b = FakeBridge().conversationTransport;
    final sa = ConversationState(), sb = ConversationState();
    snapshot(sa, 'same', 81, 100);
    snapshot(sb, 'same', 81, 100);
    final gate = Completer<dynamic>();
    a.historyHandler = (_, __, ___) => gate.future;
    b.historyHandler = (_, __, ___) async => page('same', 61, 80);
    final ha = ConversationHistory(
        transport: a,
        sessionId: 'same',
        state: sa,
        view: ConversationViewState());
    final hb = ConversationHistory(
        transport: b,
        sessionId: 'same',
        state: sb,
        view: ConversationViewState());
    final first = ha.loadOlder();
    expect(identical(first, ha.loadOlder()), isTrue);
    await hb.loadOlder();
    expect(sa.oldestRowId, 81);
    expect(sb.oldestRowId, 61);
    gate.complete(page('same', 41, 80));
    await first;
    expect(sa.oldestRowId, 41);
    expect(a.historyRequests.length, 1);
    expect(b.historyRequests.length, 1);
    ha.dispose();
    hb.dispose();
  });

  test('epoch changes discard pending pages and do not reuse old reading IDs',
      () async {
    final transport = FakeBridge().conversationTransport,
        state = ConversationState();
    snapshot(state, 'old', 801, 860);
    final view = ConversationViewState()
      ..following = false
      ..anchor = '450'
      ..logEpoch = 'old';
    view.expandedTurns[450] = true;
    final history = ConversationHistory(
        transport: transport, sessionId: 'task', state: state, view: view);
    final gate = Completer<dynamic>();
    transport.historyHandler = (_, __, ___) => gate.future;
    final restoring = history.restoreReading();
    snapshot(state, 'new', 850, 900);
    gate.complete(page('old', 601, 800));
    await restoring;
    expect(state.oldestRowId, 850);
    expect(view.following, isTrue);
    expect(view.anchor, isNull);
    expect(view.expandedTurns, isEmpty);
    expect(view.logEpoch, 'new');
    expect(history.notice, ReadingNotice.historyChanged);
    expect(history.blocksViewport, isFalse);
    history.dispose();
  });

  test('failed and nonadvancing pages stop recovery and allow explicit retry',
      () async {
    final transport = FakeBridge().conversationTransport,
        state = ConversationState();
    snapshot(state, 'epoch', 801, 860);
    final view = ConversationViewState()
      ..following = false
      ..anchor = '450';
    final history = ConversationHistory(
        transport: transport, sessionId: 'task', state: state, view: view);
    transport.historyHandler =
        (_, __, ___) async => throw StateError('offline');
    await history.restoreReading();
    expect(history.restoreFailed, isTrue);
    expect(view.anchor, '450');
    transport.historyHandler = (_, __, ___) async => page('epoch', 801, 820);
    await history.restoreReading();
    expect(history.restoreFailed, isTrue);
    expect(transport.historyRequests.length, 2);
    transport.historyHandler =
        (_, before, ___) async => page('epoch', 401, before! - 1);
    await history.restoreReading();
    expect(history.blocksViewport, isFalse);
    expect(view.following, isFalse);
    expect(view.anchor, '450');
    history.dispose();
  });

  test('Latest cancels recovery and late pages do not restart its loop',
      () async {
    final transport = FakeBridge().conversationTransport,
        state = ConversationState();
    snapshot(state, 'epoch', 801, 860);
    final view = ConversationViewState()
      ..following = false
      ..anchor = '20';
    final history = ConversationHistory(
        transport: transport, sessionId: 'task', state: state, view: view);
    final gate = Completer<dynamic>();
    transport.historyHandler = (_, __, ___) => gate.future;
    final restoring = history.restoreReading();
    history.showLatest();
    gate.complete(page('epoch', 601, 800));
    await restoring;
    expect(view.following, isTrue);
    expect(history.blocksViewport, isFalse);
    expect(transport.historyRequests.length, 1);
    history.dispose();
  });

  test('disposed page cannot mutate history after navigation', () async {
    final transport = FakeBridge().conversationTransport,
        state = ConversationState();
    snapshot(state, 'epoch', 81, 100);
    final history = ConversationHistory(
        transport: transport,
        sessionId: 'task',
        state: state,
        view: ConversationViewState());
    final gate = Completer<dynamic>();
    transport.historyHandler = (_, __, ___) => gate.future;
    final loading = history.loadOlder();
    history.dispose();
    gate.complete(page('epoch', 1, 80));
    expect(await loading, HistoryPageResult.stale);
    expect(state.oldestRowId, 81);
  });

  test('missing saved rows and changed saved epochs have explicit notices',
      () async {
    final transport = FakeBridge().conversationTransport,
        state = ConversationState();
    snapshot(state, 'epoch', 1, 100);
    final missing = ConversationViewState()
      ..following = false
      ..anchor = '101';
    final changed = ConversationViewState()
      ..following = false
      ..anchor = '20'
      ..logEpoch = 'older';
    final hm = ConversationHistory(
        transport: transport, sessionId: 'task', state: state, view: missing);
    final hc = ConversationHistory(
        transport: transport, sessionId: 'task', state: state, view: changed);
    await hm.restoreReading();
    await hc.restoreReading();
    expect(hm.notice, ReadingNotice.anchorMissing);
    expect(hc.notice, ReadingNotice.historyChanged);
    expect(transport.historyRequests, isEmpty);
    hm.dispose();
    hc.dispose();
  });
}
