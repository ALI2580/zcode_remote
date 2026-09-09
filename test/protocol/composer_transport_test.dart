import 'dart:async';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

/// Full Channel encoding/decoding with a synthetic peer; no network is opened.
class _Bridge implements BridgeSession {
  _Bridge() {
    channels = ChannelClient(sendBody: (body) {
      final reader = ValueReader(body);
      final header = decodeValue(reader) as List;
      final args = decodeValue(reader) as List;
      if (header.first != ChannelClient.reqPromise) return;
      final method = header[3] as String;
      queries.add((channel: header[2] as String, method: method, args: args));
      final id = header[1] as int;
      void respond(dynamic value) {
        final writer = ValueWriter();
        encodeValue(writer, [ChannelClient.resPromiseSuccess, id]);
        encodeValue(writer, value);
        channels.handleMessage(writer.toBytes());
      }

      if (method == 'sendConversationCommandV4') {
        final packet = (args.single as Map).cast<String, dynamic>();
        commands.add(packet);
        command?.call(packet, respond);
      } else if (method == 'prepareWorkspace') {
        preparations.add((args.single as Map).cast<String, dynamic>());
        prepare?.call(respond);
      } else {
        respond(method == 'helloConversationV4'
            ? {'connectionId': 'synthetic'}
            : {});
      }
    });
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resInitialize]);
    channels.handleMessage(writer.toBytes());
  }
  @override
  late final ChannelClient channels;
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  final commands = <Map<String, dynamic>>[];
  final queries = <({String channel, String method, List args})>[];
  final preparations = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic>, void Function(dynamic))? command;
  void Function(void Function(dynamic))? prepare;
  @override
  Future<void> waitHealthy(
      {Duration timeout = const Duration(seconds: 45)}) async {
    if (degraded.value != null) {
      degraded.value = null;
      recovered.value++;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('usage statistics serialize exact scopes on usage-stats channel',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
    await transport.appUsageSnapshot('all', 'Asia/Shanghai');
    await transport.codingUsageSnapshot({
      'preferredProviderId': 'builtin:bigmodel-coding-plan',
      'organizationId': 'org',
      'projectId': 'project'
    }, '30d', 'America/New_York');
    expect(
        bridge.queries.map((q) => q.channel), ['usage-stats', 'usage-stats']);
    expect(bridge.queries.map((q) => q.method),
        ['getAppUsageSnapshot', 'getCodingPlanUsageSnapshot']);
    expect(bridge.queries.first.args, [
      {'range': 'all', 'timeZone': 'Asia/Shanghai'}
    ]);
    expect(bridge.queries.last.args, [
      {
        'preferredProviderId': 'builtin:bigmodel-coding-plan',
        'organizationId': 'org',
        'projectId': 'project',
        'range': '30d',
        'customStartDate': null,
        'customEndDate': null,
        'timeZone': 'America/New_York'
      }
    ]);
    bridge.channels.dispose();
  });
  test('Coding Plan reset RPCs preserve scope, type and the supplied retry ID',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspacePath': 'unused'});
    const source = {
      'preferredProviderId': 'builtin:zai-coding-plan',
      'organizationId': 'organization',
      'projectId': 'project'
    };
    await transport.planResetStatus(source);
    await transport.requestPlanResetOpportunity(source, 'opportunity-retry');
    await transport.usePlanReset(source,
        resetType: 'WEEK', idempotencyKey: 'same-retry');
    await transport.usePlanReset(source,
        resetType: 'FIVE_HOUR', idempotencyKey: 'another-retry');
    await transport.markPlanResetHistoryRead(source);
    expect(bridge.queries.map((e) => e.channel).toSet(), {Channels.usageStats});
    expect(bridge.queries.map((e) => e.method), [
      'getCodingPlanResetStatus',
      'requestCodingPlanResetOpportunity',
      'useCodingPlanReset',
      'useCodingPlanReset',
      'markCodingPlanResetHistoryRead'
    ]);
    expect(bridge.queries[0].args, [source]);
    expect(bridge.queries[1].args, [
      {...source, 'idempotencyKey': 'opportunity-retry'}
    ]);
    expect(bridge.queries[2].args, [
      {...source, 'idempotencyKey': 'same-retry', 'resetType': 'WEEK'}
    ]);
    expect(bridge.queries[3].args, [
      {...source, 'idempotencyKey': 'another-retry', 'resetType': 'FIVE_HOUR'}
    ]);
    expect(bridge.queries[4].args, [source]);
    expect(bridge.commands, isEmpty);
    bridge.channels.dispose();
  });

  test(
      'team discovery and scoped quota use the official read-only Channel arguments',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {});
    await transport.teamPlanProducts('zai');
    expect(bridge.queries.single.channel, Channels.codingPlanSubscription);
    expect(bridge.queries.single.method, 'getEnterprisePricing');
    expect(bridge.queries.single.args, [
      {'authenticated': true, 'family': 'zai'}
    ]);
    await transport.entitlementSnapshot('builtin:zai-coding-plan',
        organizationId: 'org', projectId: 'project');
    expect(bridge.queries.last.args, [
      {
        'includeSubscription': true,
        'preferredProviderId': 'builtin:zai-coding-plan',
        'requirePreferredProvider': true,
        'allowDisabledPreferredProvider': true,
        'allowEnvApiKey': false,
        'organizationId': 'org',
        'projectId': 'project'
      }
    ]);
    expect(bridge.commands, isEmpty);
    bridge.channels.dispose();
  });

  test(
      'model schema and stop preserve device transport, workspace scope and session identity',
      () async {
    final a = _Bridge();
    final b = _Bridge();
    const scope = {
      'workspacePath': 'D:/Synthetic',
      'workspaceIdentity': 'same-workspace'
    };
    final ta = ConversationTransport(session: a, scope: scope);
    final tb = ConversationTransport(session: b, scope: scope);
    a.command = (packet, respond) =>
        respond({'status': 'accepted', 'revisionAtDecision': 8});
    b.command = (packet, respond) =>
        respond({'status': 'accepted', 'revisionAtDecision': 2});
    a.prepare = (respond) => respond({
          'configOptions': [
            {
              'id': 'model',
              'category': 'model',
              'type': 'select',
              'currentValue': 'p/model',
              'options': [
                {
                  'value': 'p/model',
                  'name': 'Model',
                  'origin': 'native',
                  'modelProviderId': 'p',
                  'modelProviderName': 'Provider',
                  'modelThoughtLevels': ['off', 'high'],
                  'modelDefaultThoughtLevel': 'high'
                }
              ]
            }
          ]
        });
    final prep = await ta.prepareWorkspace();
    expect(a.preparations.single, scope);
    final option = prep.option('model')!.options.single;
    expect(option.origin, 'native');
    expect(option.modelThoughtLevels, ['off', 'high']);
    expect(option.modelDefaultThoughtLevel, 'high');
    await ta.switchModelConfig('same-session',
        provider: 'p', model: 'model', thought: 'high');
    await tb.stop('same-session', expectedForegroundExecutionId: 'b-execution');
    await ta.switchCollaborationMode('same-session', 'plan');
    expect(a.commands.first['workspaceIdentity'], 'same-workspace');
    expect((a.commands.first['envelope'] as Map)['sessionId'], 'same-session');
    expect((a.commands.last['envelope'] as Map)['baseRevision'], 9);
    expect((b.commands.single['envelope'] as Map)['payload'],
        {'expectedForegroundExecutionId': 'b-execution'});
    expect((a.commands.first['envelope'] as Map)['clientId'],
        isNot((b.commands.single['envelope'] as Map)['clientId']));
  });

  test('healthy command timeout never retries on the actual channel transport',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
    await expectLater(
        transport.sendCommand('session', 'sendText', {'text': 'one'},
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()));
    expect(bridge.commands, hasLength(1));
  });

  test(
      'degraded timeout replays the same command identity for server deduplication',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
    bridge.command = (packet, respond) {
      if (bridge.commands.length == 1) {
        bridge.degraded.value = 'synthetic-drop';
      } else {
        respond({'status': 'duplicate', 'revisionAtDecision': 1});
      }
    };
    final ack = await transport.sendCommand(
        'session', 'sendText', {'text': 'one'},
        timeout: const Duration(milliseconds: 10));
    expect(ack['status'], 'duplicate');
    expect(bridge.commands, hasLength(2));
    expect(bridge.commands.first['envelope'], bridge.commands.last['envelope']);
  });

  test(
      'reasoning rejection makes only one command and never guesses another effort',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {});
    bridge.command = (packet, respond) => respond({
          'status': 'rejected',
          'message': 'Unsupported reasoning effort',
          'revisionAtDecision': 1
        });
    final ack = await transport.switchModelConfig('session',
        provider: 'p', model: 'model', thought: 'high');
    expect(ack['status'], 'rejected');
    expect(bridge.commands, hasLength(1));
  });

  test('prepare cache discards old response after refresh and bridge recovery',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {});
    final replies = <void Function(dynamic)>[];
    bridge.prepare = replies.add;
    final first = transport.prepareWorkspace();
    await Future<void>.delayed(Duration.zero);
    bridge.recovered.value++;
    final second = transport.prepareWorkspace(refresh: true);
    await Future<void>.delayed(Duration.zero);
    replies[1]({'configOptions': [], 'stamp': 'new'});
    await second;
    replies[0]({'configOptions': [], 'stamp': 'old'});
    await first;
    expect((await transport.prepareWorkspace()).raw['stamp'], 'new');
  });

  test(
      'duplicate create receipt with session result is a successful first send',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {});
    bridge.command = (packet, respond) => respond({
          'status': 'duplicate',
          'result': {'sessionId': 'created'},
          'revisionAtDecision': 1
        });
    expect(await transport.createSession('workspace', firstText: 'hello'),
        'created');
    expect((bridge.commands.single['envelope'] as Map)['payload'], {
      'workspaceId': 'workspace',
      'firstInput': {'text': 'hello'}
    });
  });
}
