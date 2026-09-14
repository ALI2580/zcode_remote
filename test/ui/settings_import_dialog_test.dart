import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/settings_import.dart';
import 'package:zcode_remote/ui/settings_import_dialog.dart';

class _FakeSync implements SettingsSyncService {
  int imports = 0;

  @override
  Future<Object?> detect({
    String? workspacePath,
    String? workspaceIdentity,
    required List<String> categories,
    required String intent,
  }) async => {
        'agents': [
          {
            'agent': 'codexCli',
            'name': 'Codex CLI',
            'categories': [
              {
                'category': 'mcpServers',
                'sourceRoots': [
                  {
                    'scope': 'global',
                    'path': 'C:/Users/test/.codex/mcp',
                    'mcpServers': [
                      {
                        'name': 'docs',
                        'path': 'C:/Users/test/.codex/mcp/docs.json',
                        'importable': true,
                      },
                      {
                        'name': 'exists',
                        'path': 'C:/Users/test/.codex/mcp/exists.json',
                        'importable': false,
                      },
                    ],
                  }
                ],
              }
            ],
          }
        ],
      };

  @override
  Future<Object?> importSelected({
    String? workspacePath,
    String? workspaceIdentity,
    required List<Map<String, dynamic>> selections,
  }) async {
    imports++;
    expect(selections.single['mcpServerPaths'], [
      'C:/Users/test/.codex/mcp/docs.json'
    ]);
    return {
      'successCount': 1,
      'skippedCount': 0,
      'failedCount': 0,
      'taskResults': [
        {
          'mcpServerResults': [
            {
              'name': 'docs',
              'path': 'docs.json',
              'status': 'imported',
            }
          ]
        }
      ],
    };
  }
}

void main() {
  testWidgets('import dialog supports resource selection and result counts',
      (tester) async {
    final service = _FakeSync();
    final controller = ExternalAgentImportController(
      service: service,
      category: 'mcpServers',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SettingsImportDialog(controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Import MCP servers'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('docs'), findsNothing);
    await tester.tap(find.text('Codex CLI'));
    await tester.pumpAndSettle();
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('exists'), findsOneWidget);
    await tester.tap(find.text('docs'));
    await tester.pump();
    expect(controller.selectedCount, 1);
    await tester.tap(find.byKey(const ValueKey('import-submit')));
    await tester.pumpAndSettle();
    expect(service.imports, 1);
    expect(find.textContaining('Imported'), findsWidgets);
    expect(find.textContaining('docs.json'), findsOneWidget);
  });
}
