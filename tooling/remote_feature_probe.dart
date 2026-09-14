import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/entitlement.dart';
import 'package:zcode_remote/protocol/file_changes.dart';
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
  final fileChangesOnly =
      Platform.environment['ZCODE_PROBE_FILE_CHANGES_ONLY'] == 'true';
  final gitSummaryOnly =
      Platform.environment['ZCODE_PROBE_GIT_SUMMARY_ONLY'] == 'true';
  final rewindPreviewOnly =
      Platform.environment['ZCODE_PROBE_REWIND_PREVIEW_ONLY'] == 'true';
  final settingsOnly =
      Platform.environment['ZCODE_PROBE_SETTINGS_ONLY'] == 'true';
  final mcpStatusOnly =
      Platform.environment['ZCODE_PROBE_MCP_STATUS_ONLY'] == 'true';
  final interactionsOnly =
      Platform.environment['ZCODE_PROBE_INTERACTIONS_ONLY'] == 'true';
  final modelProviderOnly =
      Platform.environment['ZCODE_PROBE_MODEL_PROVIDER_ONLY'] == 'true';
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
      if (rewindPreviewOnly) {
        stage = 'workspace rewind sweep';
        final previews = <Map<String, dynamic>>[];
        var workspacesScanned = 0;
        var sessionsScanned = 0;
        var changeSummaryCandidates = 0;
        var failedWorkspaces = 0;
        for (final workspace in workspaces) {
          final scope = <String, dynamic>{
            if (workspace['workspacePath'] is String)
              'workspacePath': workspace['workspacePath'],
            if (workspace['workspaceIdentity'] is String)
              'workspaceIdentity': workspace['workspaceIdentity'],
          };
          final key =
              '${workspace['workspaceIdentity'] ?? workspace['workspacePath']}';
          BridgeSession? bridge;
          try {
            bridge = await client.openBridge(key);
            final transport = bridge.conversation(scope);
            workspacesScanned++;
            stage = 'sessions index for rewind sweep';
            final index = await transport.subscribeSessionsIndex();
            await _ready(index.state, () => index.state.ready);
            for (final task in index.state.list.take(12)) {
              sessionsScanned++;
              stage = 'conversation rewind sweep';
              ConversationSubscription? sub;
              try {
                sub = await transport.subscribe(task.sessionId);
                final conversationSub = sub;
                await _ready(
                    conversationSub.state, () => conversationSub.state.ready);
                final row = conversationSub.state.rows
                    .where((row) => row['kind'] == 'changeSummary')
                    .firstOrNull;
                if (row == null) continue;
                changeSummaryCandidates++;
                final rowId = row['rowId'];
                final entityId = row['entityId'];
                if (rowId is! int) {
                  previews.add({'rowIdInvalid': true});
                  continue;
                }
                final target = <String, dynamic>{
                  'rowId': rowId,
                  if (entityId != null) 'entityId': entityId,
                };
                final raw = await transport.fileRewindPreview(
                  task.sessionId,
                  target: target,
                  baseRevision: conversationSub.state.revision,
                  baseLogEpoch: conversationSub.state.logEpoch,
                );
                final parsed = parseFileRewindPreview(raw);
                previews.add({
                  'rowId': true,
                  'entityId': entityId != null,
                  'canApply': parsed.canApply,
                  'safeCount': parsed.safeFiles.length,
                  'unsafeCount': parsed.unsafeFiles.length,
                  'ignoredCount': parsed.ignoredFiles.length,
                  'problems': parsed.problems.length,
                });
              } catch (error) {
                previews.add({
                  'readFailed': true,
                  'error': _safeError(error),
                });
              } finally {
                await sub?.dispose();
              }
              if (previews.length >= 3) break;
            }
            await index.dispose();
          } catch (error) {
            failedWorkspaces++;
            previews.add({
              'workspaceReadFailed': true,
              'error': _safeError(error),
            });
          } finally {
            bridge?.dispose();
          }
          if (previews.length >= 3) break;
        }
        report['rewindWorkspaceSweep'] = {
          'workspacesScanned': workspacesScanned,
          'sessionsScanned': sessionsScanned,
          'changeSummaryCandidates': changeSummaryCandidates,
          'failedWorkspaces': failedWorkspaces,
          'previews': previews,
        };
        return;
      }
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
          _count('sessions', transport.sessionReferences()),
        ]);
        report['slashCommands'] = [
          for (final command in prep.slashCommands)
            {'name': command.name, 'source': command.source},
        ];
        return;
      }
      if (fileChangesOnly) {
        stage = 'sessions index';
        final index = await transport.subscribeSessionsIndex();
        await _ready(index.state, () => index.state.ready);
        final attempts = <Map<String, dynamic>>[];
        var scanned = 0;
        for (final task in index.state.list.take(8)) {
          scanned++;
          stage = 'conversation file changes';
          ConversationSubscription? sub;
          try {
            sub = await transport.subscribe(task.sessionId);
            final conversationSub = sub;
            await _ready(
                conversationSub.state, () => conversationSub.state.ready);
            final rows = conversationSub.state.rows
                .where((row) => row['kind'] == 'changeSummary')
                .take(2)
                .toList();
            if (rows.isEmpty) {
              attempts.add({'changeSummaryRows': 0});
              continue;
            }
            for (final row in rows) {
              final rowId = row['rowId'];
              final entityId = row['entityId'];
              if (rowId is! int) {
                attempts.add({'rowIdInvalid': true});
                continue;
              }
              final target = <String, dynamic>{
                'rowId': rowId,
                if (entityId != null) 'entityId': entityId,
              };
              try {
                final raw = await transport.fileChanges(
                  task.sessionId,
                  target: target,
                  baseRevision: conversationSub.state.revision,
                  baseLogEpoch: conversationSub.state.logEpoch,
                );
                final parsed = parseFileChanges(raw);
                attempts.add({
                  'rowId': true,
                  'entityId': entityId != null,
                  'files': parsed.files,
                  'additions': parsed.additions,
                  'deletions': parsed.deletions,
                  'state': parsed.state,
                  'fileState': parsed.fileState,
                  'problems': parsed.problems.length,
                  'shape': _shape(raw),
                });
              } catch (error) {
                attempts.add({
                  'readFailed': true,
                  'error': _safeError(error),
                });
              }
            }
            if (attempts.length >= 3) break;
          } finally {
            await sub?.dispose();
          }
        }
        report['scannedTasks'] = scanned;
        report['fileChangesAttempts'] = attempts;
        await index.dispose();
        return;
      }
      if (gitSummaryOnly) {
        stage = 'git summary';
        await bridge.channels.ready.timeout(const Duration(seconds: 15));
        final raw = await bridge.channels.call(
          Channels.git,
          'refresh',
          [
            {
              'workspacePath': scope['workspacePath'],
              if (scope['workspaceIdentity'] != null)
                'workspaceIdentity': scope['workspaceIdentity'],
              'includeIdentity': false,
              'includeBranchComparison': false,
            }
          ],
          timeout: const Duration(seconds: 20),
        );
        final summary =
            raw is Map && raw['summary'] is Map ? raw['summary'] as Map : null;
        report['gitSummary'] = {
          'present': summary != null,
          'fields': summary == null
              ? <String>[]
              : summary.keys.map((key) => '$key').toList()
            ..sort(),
          'gitAvailable': summary?['isGitAvailable'] == true,
          'repository': summary?['isRepository'] == true,
          'dirty': summary?['isDirty'] == true,
          'ahead': summary?['ahead'] is num,
          'behind': summary?['behind'] is num,
          'branchType': summary?['headRefType'],
        };
        return;
      }
      if (rewindPreviewOnly) {
        stage = 'sessions index';
        final index = await transport.subscribeSessionsIndex();
        await _ready(index.state, () => index.state.ready);
        final previews = <Map<String, dynamic>>[];
        var scanned = 0;
        for (final task in index.state.list.take(8)) {
          scanned++;
          stage = 'conversation rewind preview';
          ConversationSubscription? sub;
          try {
            sub = await transport.subscribe(task.sessionId);
            final conversationSub = sub;
            await _ready(
                conversationSub.state, () => conversationSub.state.ready);
            final row = conversationSub.state.rows
                .where((row) => row['kind'] == 'changeSummary')
                .firstOrNull;
            if (row == null) continue;
            final rowId = row['rowId'];
            final entityId = row['entityId'];
            if (rowId is! int) {
              previews.add({'rowIdInvalid': true});
              continue;
            }
            final target = <String, dynamic>{
              'rowId': rowId,
              if (entityId != null) 'entityId': entityId,
            };
            final raw = await transport.fileRewindPreview(
              task.sessionId,
              target: target,
              baseRevision: conversationSub.state.revision,
              baseLogEpoch: conversationSub.state.logEpoch,
            );
            final parsed = parseFileRewindPreview(raw);
            previews.add({
              'rowId': true,
              'entityId': entityId != null,
              'canApply': parsed.canApply,
              'safeCount': parsed.safeFiles.length,
              'unsafeCount': parsed.unsafeFiles.length,
              'ignoredCount': parsed.ignoredFiles.length,
              'problems': parsed.problems.length,
            });
          } catch (error) {
            previews.add({
              'readFailed': true,
              'error': _safeError(error),
            });
          } finally {
            await sub?.dispose();
          }
          if (previews.length >= 3) break;
        }
        report['scannedTasks'] = scanned;
        report['rewindPreviews'] = previews;
        await index.dispose();
        return;
      }
      if (interactionsOnly) {
        stage = 'sessions index';
        final index = await transport.subscribeSessionsIndex();
        await _ready(index.state, () => index.state.ready);
        final kinds = <String, int>{};
        final samples = <Map<String, dynamic>>[];
        var scanned = 0;
        for (final task in index.state.list.take(12)) {
          scanned++;
          stage = 'conversation pending interactions';
          ConversationSubscription? sub;
          try {
            sub = await transport.subscribe(task.sessionId);
            final conversationSub = sub;
            await _ready(
                conversationSub.state, () => conversationSub.state.ready);
            for (final interaction
                in conversationSub.state.pendingInteractions) {
              final kind = '${interaction['kind'] ?? 'unknown'}';
              kinds[kind] = (kinds[kind] ?? 0) + 1;
              final payload =
                  (interaction['payload'] as Map?)?.cast<String, dynamic>() ??
                      const {};
              final payloadKind = '${payload['kind'] ?? 'unknown'}';
              final options = payload['options'] is List
                  ? (payload['options'] as List).length
                  : null;
              final questions = payload['questions'] is List
                  ? (payload['questions'] as List).length
                  : null;
              final auto = interaction['autoResolution'] as Map?;
              final hookItems = payload['items'] is List
                  ? (payload['items'] as List)
                      .whereType<Map>()
                      .map((item) => item['trustState'] ?? 'unknown')
                      .toList()
                  : null;
              samples.add({
                'kind': kind,
                'payloadKind': payloadKind,
                'payloadKeys': payload.keys.map((key) => key).toList()..sort(),
                if (options != null) 'optionCount': options,
                if (questions != null) 'questionCount': questions,
                if (auto?['state'] != null)
                  'autoResolutionState': auto?['state'],
                if (hookItems != null) 'hookTrustStates': hookItems,
              });
            }
          } finally {
            await sub?.dispose();
          }
        }
        report['scannedTasks'] = scanned;
        report['interactionKinds'] = kinds;
        report['interactionSamples'] = samples;
        await index.dispose();
        return;
      }
      if (modelProviderOnly) {
        stage = 'model provider getAll';
        await bridge.channels.ready.timeout(const Duration(seconds: 15));
        final raw = await bridge.channels.call(
          Channels.modelProvider,
          'getAll',
          const [],
          timeout: const Duration(seconds: 20),
        );
        report['modelProviderWire'] = _shapeOf(raw);
        return;
      }
      if (settingsOnly) {
        stage = 'settings read';
        final raw = await bridge.channels.call(
          Channels.setting,
          'get',
          const [],
          timeout: const Duration(seconds: 20),
        );
        if (raw is Map) {
          final map = raw.cast<String, dynamic>();
          String type(Object? value) => value == null
              ? 'null'
              : value is bool
                  ? 'bool'
                  : value is num
                      ? 'number'
                      : value is String
                          ? 'string'
                          : value is List
                              ? 'list'
                              : 'map';
          report['settingsWire'] = {
            'fieldCount': map.length,
            'fields': {
              for (final entry in map.entries) entry.key: type(entry.value),
            },
            'providerFamilyShape': {
              for (final key in [
                'modelProviderFamilyModes',
                'modelProviderFamilySelectedKeys'
              ])
                key: map[key] is Map
                    ? {
                        'count': (map[key] as Map).length,
                        'keys': (map[key] as Map).keys.map((e) => '$e').toList()
                          ..sort(),
                      }
                    : null,
            },
            'knownFieldTypes': {
              for (final key in [
                'terminalInheritSystemProfile',
                'terminalFontFamily',
                'integratedTerminalShell',
                'embeddedBrowserAllowInsecureCertificates',
                'taskAutoArchiveEnabled',
                'taskAutoArchiveOlderThanDays',
                'messageStreamShowReasoning',
                'zcodeInteractionBehavior',
                'modelProviderFamilyModes',
                'modelProviderFamilySelectedKeys'
              ])
                if (map.containsKey(key)) key: type(map[key]),
            },
          };
        } else {
          report['settingsWire'] = {
            'responseType': '${raw.runtimeType}',
          };
        }
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
      if (mcpStatusOnly) {
        stage = 'mcp status';
        final raw = await bridge.channels.call(
          Channels.mcpSync,
          'listWorkspaceMcpServerStatuses',
          [
            {
              'workspacePath': scope['workspacePath'],
              if (scope['workspaceIdentity'] != null)
                'workspaceIdentity': scope['workspaceIdentity'],
              'mode': 'status',
            }
          ],
          timeout: const Duration(seconds: 30),
        );
        final statuses = raw is Map && raw['statuses'] is List
            ? (raw['statuses'] as List).whereType<Map>().toList()
            : const <Map>[];
        report['mcpStatus'] = {
          'responseType': '${raw.runtimeType}',
          'responseKeys': raw is Map ? raw.keys.map((e) => '$e').toList() : [],
          'count': statuses.length,
          'entries': [
            for (final status in statuses.take(20))
              {
                'fields': status.keys.map((e) => '$e').toList()..sort(),
                'name': status['name'] is String,
                'status': status['status'],
                'enabled': status['enabled'] is bool,
                'toolCount': status['toolCount'] is num,
              }
          ],
        };
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
              'build/artifacts/${statisticsOnly ? 'official-usage-statistics-probe' : fileChangesOnly ? 'official-file-changes-probe' : rewindPreviewOnly ? 'official-rewind-preview-probe' : settingsOnly ? 'official-settings-probe' : mcpStatusOnly ? 'official-mcp-status-probe' : connectionOnly ? 'official-connection-probe' : gitSummaryOnly ? 'official-git-summary-probe' : filesOnly ? 'official-parity-files-probe' : modelProviderOnly ? 'official-model-provider-probe' : interactionsOnly ? 'official-interactions-probe' : 'official-parity-probe'}${label == null ? '' : '-$label'}.json')
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

Map<String, dynamic> _shapeOf(Object? value) {
  if (value == null) return {'type': 'null'};
  if (value is bool || value is num || value is String) {
    return {'type': '${value.runtimeType}'};
  }
  if (value is List) {
    return {
      'type': 'list',
      'length': value.length,
      if (value.isNotEmpty) 'item': _shapeOf(value.first),
    };
  }
  if (value is Map) {
    return {
      'type': 'map',
      'fields': {
        for (final entry in value.entries)
          '${entry.key}': _shapeOf(entry.value),
      },
    };
  }
  return {'type': '${value.runtimeType}'};
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
