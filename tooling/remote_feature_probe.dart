import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/entitlement.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

/// Opt-in read-only evidence. Output excludes links, task content, identifiers,
/// provider secrets and filesystem paths. Never invokes conversation commands.
void main() {
  final url = Platform.environment['ZEMOTE_PROBE_URL'];
  final filesOnly = Platform.environment['ZCODE_PROBE_FILES_ONLY'] == 'true';
  final statisticsOnly =
      Platform.environment['ZCODE_PROBE_STATISTICS_ONLY'] == 'true';
  final connectionOnly =
      Platform.environment['ZCODE_PROBE_CONNECTION_ONLY'] == 'true';
  final alias = Platform.environment['ZCODE_PROBE_ALIAS'];
  final label = const ['ALI', 'ROG-STRIX'].contains(alias) ? alias : null;
  test('official feature data sources (read-only)', () async {
    if (url == null || url.isEmpty) return;
    final client = ZemoteClient(ZemoteConnectionParams.parse(url)!);
    final report = <String, dynamic>{};
    if (label != null) report['remoteDevice'] = label;
    var stage = 'connect';
    try {
      await client.connect();
      await client.waitPaired();
      stage = 'bootstrap';
      final bootstrap = await client.bootstrap();
      final workspaces =
          (bootstrap['workspaces'] as List).whereType<Map>().toList();
      report['workspaceCount'] = workspaces.length;
      report['globalTaskIndexAvailable'] = bootstrap['tasks'] is List;
      if (bootstrap['tasks'] case final List tasks) {
        report['globalTaskCount'] = tasks.length;
        report['taskIndexFields'] = tasks
            .whereType<Map>()
            .expand((e) => e.keys.map((e) => '$e'))
            .toSet()
            .toList()
          ..sort();
      }
      if (workspaces.isEmpty) return;
      final workspace = workspaces
              .where((e) => '${e['workspacePath']}'
                  .replaceAll('\\', '/')
                  .endsWith('/ZcodeRemote'))
              .firstOrNull ??
          workspaces.first;
      final scope = <String, dynamic>{
        if (workspace['workspacePath'] is String)
          'workspacePath': workspace['workspacePath'],
        if (workspace['workspaceIdentity'] is String)
          'workspaceIdentity': workspace['workspaceIdentity'],
      };
      final key =
          '${workspace['workspaceIdentity'] ?? workspace['workspacePath']}';
      stage = 'bridge';
      final bridge = await client.openBridge(key);
      final transport = bridge.conversation(scope);
      if (connectionOnly) {
        stage = 'channel initialization';
        await bridge.channels.ready.timeout(const Duration(seconds: 15));
        report['channelInitialized'] = true;
        stage = 'conversation handshake';
        await transport.handshake();
        report['conversationHandshake'] = true;
        stage = 'workspace configuration';
        final prep = await transport.prepareWorkspace();
        report['configOptions'] = prep.configOptions.length;
        stage = 'reference catalogs';
        report['references'] = await Future.wait([
          _count('files', transport.workspaceFiles()),
          _count('skills', transport.skillReferences(null)),
          _count('plugins', transport.pluginReferences(null)),
        ]);
        return;
      }
      if (filesOnly) {
        stage = 'files with 60 second deadline';
        final watch = Stopwatch()..start();
        try {
          final result = await bridge.channels.call(
              Channels.file,
              'listWorkspaceFiles',
              [
                {'rootPath': scope['workspacePath']}
              ],
              timeout: const Duration(seconds: 60));
          report['files'] = {
            'elapsedMs': watch.elapsedMilliseconds,
            'responseType': '${result.runtimeType}',
            'count': result is List ? result.length : null,
            'entryFields':
                result is List && result.isNotEmpty && result.first is Map
                    ? (result.first as Map).keys.toList()
                    : []
          };
        } catch (error) {
          final message =
              error is ChannelRpcError ? error.message.toLowerCase() : '';
          report['files'] = {
            'elapsedMs': watch.elapsedMilliseconds,
            'errorType': '${error.runtimeType}',
            'unknownMethod': message.contains('method not found') ||
                message.contains('unknown'),
            'filesystemFailure':
                message.contains('enoent') || message.contains('eacces')
          };
        }
        return;
      }
      stage = 'family selection';
      final selection = await transport.providerFamilySelection();
      report['familySelectionFields'] = selection.keys.toList();
      if (statisticsOnly) {
        for (final provider in [
          'builtin:zai-coding-plan',
          'builtin:bigmodel-coding-plan'
        ]) {
          var source = EntitlementSource.resolve(provider, selection);
          if (source == null) continue;
          if (source.needsTeamResolution) {
            source = source.resolveTeamProducts(
                await transport.teamPlanProducts(source.family));
          }
          if (source == null) continue;
          final entitlement = EntitlementSnapshot.parse(
              await transport.entitlementSnapshot(source.providerId,
                  organizationId: source.organizationId,
                  projectId: source.projectId));
          if (entitlement == null ||
              !source.accepts(entitlement) ||
              !entitlement.visible) {
            continue;
          }
          report['statisticsProvider'] = source.providerId;
          final args = {
            'preferredProviderId': source.providerId,
            if (source.organizationId != null)
              'organizationId': source.organizationId,
            if (source.projectId != null) 'projectId': source.projectId,
          };
          stage = 'reset status (read only)';
          try {
            final reset = await transport.planResetStatus(args);
            report['resetShape'] = _shape(reset);
            if (reset is Map) {
              report['resetCounts'] = {
                for (final key in [
                  'availableFiveHourResets',
                  'availableWeekResets'
                ])
                  key: reset[key] is List ? (reset[key] as List).length : null,
              };
            }
          } catch (error) {
            report['resetError'] = _safeError(error);
          }
          stage = 'Coding Plan statistics';
          final usage = await bridge.channels.call(
              Channels.usageStats,
              'getCodingPlanUsageSnapshot',
              [
                {
                  ...args,
                  'range': '7d',
                  'customStartDate': null,
                  'customEndDate': null,
                  'timeZone': 'Asia/Shanghai'
                }
              ],
              timeout: const Duration(seconds: 60));
          report['codingShape'] = _shape(usage);
          if (usage is Map && usage['activity'] is Map) {
            report['codingActivitySummary'] =
                _numeric((usage['activity'] as Map)['summary']);
          }
        }
        stage = 'application statistics';
        final app = await bridge.channels.call(
            Channels.usageStats,
            'getAppUsageSnapshot',
            [
              {'range': '7d', 'timeZone': 'Asia/Shanghai'}
            ],
            timeout: const Duration(seconds: 60));
        report['appShape'] = _shape(app);
        if (app is Map) report['appSummary'] = _numeric(app['summary']);
        return;
      }
      final quotaReports = <Map<String, dynamic>>[];
      for (final provider in [
        'builtin:zai-coding-plan',
        'builtin:zai-start-plan',
        'builtin:bigmodel-coding-plan',
        'builtin:bigmodel-start-plan'
      ]) {
        final source = EntitlementSource.resolve(provider, selection);
        if (source == null) continue;
        stage = 'entitlements';
        try {
          final raw = await transport.entitlementSnapshot(provider,
              organizationId: source.organizationId,
              projectId: source.projectId);
          final snapshot = EntitlementSnapshot.parse(raw);
          quotaReports.add({
            'provider': provider,
            'team': source.isTeam,
            'sourceMatched': snapshot != null && source.accepts(snapshot),
            'visible': snapshot?.visible,
            'reason': snapshot?.unavailableReason,
            'fiveHourRemaining': snapshot?.fiveHour?.remainingPercent,
            'weeklyRemaining': snapshot?.weekly?.remainingPercent,
            'toolRemaining': snapshot?.monthlyTool?.remainingPercent,
            'mcpRemaining': snapshot?.mcpAggregate?.remainingPercent,
            'startLimitCount': snapshot?.startPlanLimits.length
          });
        } catch (_) {
          quotaReports.add({'provider': provider, 'readFailed': true});
        }
      }
      report['entitlements'] = quotaReports;
      stage = 'sessions index';
      final index = await transport.subscribeSessionsIndex();
      await _ready(index.state, () => index.state.ready);
      final usage = <Map<String, dynamic>>[];
      for (final task in index.state.list.take(8)) {
        stage = 'conversation usage';
        final sub = await transport.subscribe(task.sessionId);
        await _ready(sub.state, () => sub.state.ready);
        final window = sub.state.usage?['contextWindow'];
        final provider = sub.state.config?['provider'];
        final breakdown = window is Map ? window['breakdown'] : null;
        usage.add({
          'provider': provider is String && provider.startsWith('builtin:')
              ? provider
              : 'custom-or-api',
          'usageFields': sub.state.usage?.keys.toList(),
          'contextFields': window is Map ? window.keys.toList() : [],
          'usedTokens': window is Map ? window['usedTokens'] : null,
          'maxTokens': window is Map ? window['maxTokens'] : null,
          'sources': breakdown is List
              ? [
                  for (final row in breakdown.whereType<Map>())
                    {'source': row['source'], 'chars': row['chars']}
                ]
              : null
        });
        await sub.dispose();
      }
      report['conversationUsage'] = usage;
      await index.dispose();
      stage = 'reference catalogs';
      final catalogs = await Future.wait([
        _count('files', transport.workspaceFiles()),
        _count('skills', transport.skillReferences(null)),
        _count('plugins', transport.pluginReferences(null)),
      ]);
      report['references'] = catalogs;
      stage = 'plugin overview';
      try {
        final overview = await bridge.channels
            .call(Channels.pluginManagement, 'getPluginsOverview', [scope]);
        report['pluginOverviewFields'] =
            overview is Map ? overview.keys.toList() : [];
      } catch (_) {
        report['pluginOverviewReadFailed'] = true;
      }
    } catch (error) {
      report['incompleteStage'] = stage;
      report['failureType'] = '${error.runtimeType}';
      if (statisticsOnly) report['readError'] = _safeError(error);
    } finally {
      await client.dispose();
      await Directory('build/artifacts').create(recursive: true);
      await File(
              'build/artifacts/${statisticsOnly ? 'official-usage-statistics-probe' : connectionOnly ? 'official-connection-probe' : filesOnly ? 'official-parity-files-probe' : 'official-parity-probe'}${label == null ? '' : '-$label'}.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print(
          'Read-only evidence written; stage=$stage, incomplete=${report.containsKey('incompleteStage')}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

String _safeError(Object error) =>
    (error is ChannelRpcError ? error.message : '${error.runtimeType}')
        .replaceAll(RegExp(r'https?://\S+'), '<url>')
        .replaceAll(
            RegExp(r'(sid|hash|token|apiKey|authorization)\s*[:=]\s*\S+',
                caseSensitive: false),
            '[redacted]')
        .replaceAll(RegExp(r'[a-zA-Z0-9-]{32,}'), '<identifier>');

Object? _shape(Object? value, [int depth = 0]) {
  if (depth > 8) return '<nested>';
  if (value is Map) {
    return {
      for (final key in value.keys) '$key': _shape(value[key], depth + 1)
    };
  }
  if (value is List) {
    return {
      'count': value.length,
      'samples': value.take(1).map((e) => _shape(e, depth + 1)).toList()
    };
  }
  if (value == null) return null;
  return '<${value.runtimeType}>';
}

Map<String, num> _numeric(Object? value) => value is Map
    ? {
        for (final key in value.keys)
          if (value[key] is num) '$key': value[key] as num,
      }
    : {};

Future<Map<String, dynamic>> _count(
    String kind, Future<List<Map<String, dynamic>>> value) async {
  try {
    final rows = await value;
    return {
      'kind': kind,
      'count': rows.length,
      'entryFields': rows.isEmpty ? [] : rows.first.keys.toList()
    };
  } catch (error) {
    final message = error is ChannelRpcError ? error.message.toLowerCase() : '';
    return {
      'kind': kind,
      'readFailed': true,
      'errorType': '${error.runtimeType}',
      'unknownMethod': message.contains('unknown') ||
          message.contains('not found') ||
          message.contains('not implemented'),
      'filesystemFailure':
          message.contains('enoent') || message.contains('eacces'),
    };
  }
}

Future<void> _ready(dynamic state, bool Function() ready) async {
  if (ready()) return;
  final signal = Completer<void>();
  void changed() {
    if (ready() && !signal.isCompleted) signal.complete();
  }

  state.addListener(changed);
  changed();
  try {
    await signal.future.timeout(const Duration(seconds: 20));
  } finally {
    state.removeListener(changed);
  }
}
