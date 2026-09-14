import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/settings_import.dart';

import '../ui/fake_features.dart';

class FakeSettingsSync implements SettingsSyncService {
  int detectCalls = 0;
  int importCalls = 0;
  Object? detectResponse;
  Object? importResponse;
  Object? detectError;
  Object? importError;
  Map<String, Object?>? lastDetect;
  Map<String, Object?>? lastImport;
  Completer<Object?>? detectGate;
  Completer<Object?>? importGate;

  @override
  Future<Object?> detect({
    String? workspacePath,
    String? workspaceIdentity,
    required List<String> categories,
    required String intent,
  }) async {
    detectCalls++;
    lastDetect = {
      'workspacePath': workspacePath,
      'workspaceIdentity': workspaceIdentity,
      'categories': categories,
      'intent': intent,
    };
    final gate = detectGate;
    if (gate != null) return gate.future;
    if (detectError != null) throw detectError!;
    return detectResponse;
  }

  @override
  Future<Object?> importSelected({
    String? workspacePath,
    String? workspaceIdentity,
    required List<Map<String, dynamic>> selections,
  }) async {
    importCalls++;
    lastImport = {
      'workspacePath': workspacePath,
      'workspaceIdentity': workspaceIdentity,
      'selections': selections,
    };
    final gate = importGate;
    if (gate != null) return gate.future;
    if (importError != null) throw importError!;
    return importResponse;
  }
}

Map<String, dynamic> _discovery() => {
      'agents': [
        {
          'agent': 'codexCli',
          'name': 'Codex CLI',
          'categories': [
            {
              'category': 'skills',
              'sourceRoots': [
                {
                  'scope': 'global',
                  'path': 'C:/Users/test/.codex/skills',
                  'discoveredCount': 2,
                  'importableCount': 1,
                  'skippedCount': 1,
                  'skills': [
                    {
                      'name': 'review',
                      'path': 'C:/Users/test/.codex/skills/review',
                      'version': '1',
                      'importable': true,
                    },
                    {
                      'name': 'already-present',
                      'path': 'C:/Users/test/.codex/skills/already-present',
                      'importable': false,
                    },
                  ],
                },
                {
                  'scope': 'project',
                  'path': 'D:/Project/.agents/skills',
                  'skills': [
                    {
                      'name': 'project-review',
                      'path': 'D:/Project/.agents/skills/project-review',
                      'importable': true,
                    },
                  ],
                },
              ],
            },
          ],
        },
        {
          'agent': 'claudeCode',
          'categories': [
            {
              'category': 'skills',
              'sourceRoots': [
                {
                  'scope': 'global',
                  'path': 'C:/Users/test/.claude/skills',
                  'skills': [
                    {
                      'name': 'review',
                      'path': 'C:/Users/test/.claude/skills/review',
                      'importable': true,
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

Map<String, dynamic> _multiCategoryDiscovery() => {
      'agents': [
        {
          'agent': 'codexCli',
          'name': 'Codex CLI',
          'categories': [
            {
              'category': 'skills',
              'sourceRoots': [
                {
                  'scope': 'global',
                  'path': 'C:/Users/test/.codex/skills',
                  'skills': [
                    {
                      'name': 'review',
                      'path': 'C:/Users/test/.codex/skills/review',
                      'importable': true,
                    },
                  ],
                },
              ],
            },
            {
              'category': 'commands',
              'sourceRoots': [
                {
                  'scope': 'global',
                  'path': 'C:/Users/test/.codex/commands',
                  'commands': [
                    {
                      'name': 'review',
                      'path': 'C:/Users/test/.codex/commands/review.md',
                      'importable': true,
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

void main() {
  test('onboarding mode scans every category and keeps per-category selection',
      () async {
    final fake = FakeSettingsSync()..detectResponse = _multiCategoryDiscovery();
    final controller = ExternalAgentImportController(
      service: fake,
      category: 'skills',
      categories: const ['skills', 'commands', 'plugins', 'mcpServers'],
      workspacePath: 'D:/Project',
      workspaceIdentity: 'workspace-id',
    );
    addTearDown(controller.dispose);
    await controller.scan();
    // The onboarding entry sends the full category list in one detect.
    expect(fake.lastDetect?['categories'],
        ['skills', 'commands', 'plugins', 'mcpServers']);
    expect(controller.visibleRoots, hasLength(2));
    expect(controller.visibleRoots[0].category, 'skills');
    expect(controller.visibleRoots[1].category, 'commands');
    expect(controller.totalImportableCount, 2);

    final skillRow =
        controller.visibleRoots.firstWhere((row) => row.category == 'skills');
    final commandRow =
        controller.visibleRoots.firstWhere((row) => row.category == 'commands');
    final skillKey = controller.resourceKeysFor(skillRow).single;
    final commandKey = controller.resourceKeysFor(commandRow).single;
    expect(skillKey, isNot(commandKey));
    controller.toggleSelection(skillKey);
    controller.toggleSelection(commandKey);
    expect(controller.selections, hasLength(2));
    expect(
      controller.selections.map((selection) => selection['category']),
      containsAll(['skills', 'commands']),
    );
    // Imports go out in one wire call.
    final imported = await controller.importSelected();
    expect(imported, isTrue);
    expect(fake.importCalls, 1);
    expect((fake.lastImport?['selections'] as List), hasLength(2));
  });

  test('detect preserves official fields and selection groups payloads', () async {
    final fake = FakeSettingsSync()..detectResponse = _discovery();
    final controller = ExternalAgentImportController(
      service: fake,
      category: 'skills',
      workspacePath: 'D:/Project',
      workspaceIdentity: 'workspace-id',
    );
    addTearDown(controller.dispose);
    await controller.scan();
    expect(fake.detectCalls, 1);
    expect(fake.lastDetect?['categories'], ['skills']);
    expect(fake.lastDetect?['intent'], 'manualImport');
    expect(controller.totalImportableCount, 3);
    expect(controller.visibleRoots, hasLength(2));

    final first = controller.visibleRoots.first;
    controller.toggleExpanded(first);
    final firstKey = controller.resourceKeysFor(first).single;
    controller.toggleSelection(firstKey);
    controller.setImportMode('copy');
    controller.setImportTargetScope('project');
    expect(controller.selections, [
      {
        'agent': 'codexCli',
        'category': 'skills',
        'sourceScope': 'global',
        'targetScope': 'project',
        'importMode': 'copy',
        'skillPaths': ['C:/Users/test/.codex/skills/review'],
      }
    ]);
    expect(controller.visibleRoots.first.root.resources.last.importable, isFalse);
    expect(controller.expandedSourceKeys, isNotEmpty);
  });

  test('successful import reports nested task results and exact payload', () async {
    final fake = FakeSettingsSync()
      ..detectResponse = _discovery()
      ..importResponse = {
        'successCount': 1,
        'skippedCount': 1,
        'failedCount': 0,
        'taskResults': [
          {
            'agent': 'codexCli',
            'skillResults': [
              {
                'name': 'review',
                'path': 'review',
                'status': 'imported',
                'sourceScope': 'global',
              },
              {
                'name': 'already-present',
                'path': 'already-present',
                'status': 'skipped',
                'skipReason': 'exists',
              },
            ],
          }
        ],
      };
    final controller = ExternalAgentImportController(
      service: fake,
      category: 'skills',
      workspacePath: 'D:/Project',
    );
    addTearDown(controller.dispose);
    await controller.scan();
    controller.toggleSelection(controller.visibleResourceKeys().first);
    expect(await controller.importSelected(), isTrue);
    expect(controller.status, ExternalAgentImportStatus.complete);
    expect(controller.result?.successCount, 1);
    expect(controller.result?.taskResults, hasLength(2));
    expect(fake.lastImport?['workspacePath'], 'D:/Project');
    final selections = fake.lastImport?['selections'] as List;
    expect((selections.single as Map)['skillPaths'], isNotEmpty);
  });

  test('failed import retains selection for retry', () async {
    final fake = FakeSettingsSync()..detectResponse = _discovery();
    final controller = ExternalAgentImportController(
      service: fake,
      category: 'skills',
    );
    addTearDown(controller.dispose);
    await controller.scan();
    controller.toggleSelection(controller.visibleResourceKeys().first);
    fake.importError = StateError('import failed');
    expect(await controller.importSelected(), isFalse);
    expect(controller.status, ExternalAgentImportStatus.ready);
    expect(controller.selectedCount, 1);
    expect(controller.error.toString(), contains('import failed'));
  });

  test('late scan from old workspace cannot replace new context', () async {
    final fake = FakeSettingsSync()
      ..detectResponse = _discovery()
      ..detectGate = Completer<Object?>();
    final controller = ExternalAgentImportController(
      service: fake,
      category: 'skills',
      workspacePath: 'D:/A',
    );
    addTearDown(controller.dispose);
    final oldScan = controller.scan();
    controller.updateContext(nextWorkspacePath: 'D:/B');
    fake.detectGate!.complete({
      'agents': [
        {
          'agent': 'new',
          'categories': [
            {
              'category': 'skills',
              'sourceRoots': [
                {
                  'scope': 'global',
                  'path': 'D:/B/skills',
                  'skills': [
                    {'name': 'new', 'path': 'new', 'importable': true}
                  ],
                }
              ],
            }
          ],
        }
      ]
    });
    await oldScan;
    expect(controller.status, ExternalAgentImportStatus.idle);
    expect(controller.discovery, isNull);
  });

  test('channel adapter sends the verified detect and importSelected payloads',
      () async {
    final bridge = FeatureBridge();
    final payloads = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'settings-sync');
      payloads.add((args.single as Map).cast<String, dynamic>());
      return method == 'detect' ? _discovery() : {'successCount': 0};
    };
    final service = ChannelSettingsSyncService(bridge);
    await service.detect(
      workspacePath: 'D:/Project',
      workspaceIdentity: 'workspace',
      categories: ['skills'],
      intent: 'manualImport',
    );
    await service.importSelected(
      workspacePath: 'D:/Project',
      workspaceIdentity: 'workspace',
      selections: const [
        {
          'agent': 'codexCli',
          'category': 'skills',
          'targetScope': 'global',
          'importMode': 'symlink',
          'skillPaths': ['review'],
        }
      ],
    );
    expect(payloads[0], {
      'workspacePath': 'D:/Project',
      'workspaceIdentity': 'workspace',
      'categories': ['skills'],
      'intent': 'manualImport',
    });
    expect(payloads[1]['selections'], isA<List>());
  });
}
