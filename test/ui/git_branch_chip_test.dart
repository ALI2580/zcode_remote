import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/git_branch_chip.dart';

import 'fake_features.dart';

void main() {
  testWidgets('branch chip renders only when git is available', (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => {
          'summary': {
            'branchName': 'main',
            'headRefType': 'branch',
            'ahead': 1,
            'behind': 0,
            'isDirty': true,
            'isGitAvailable': true,
            'isRepository': true,
          }
        };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          GitBranchChip(
            session: bridge,
            scope: const {'workspacePath': 'D:/Synthetic'},
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('main'), findsOneWidget);
    expect(bridge.channels.calls.single.method, 'refresh');
    expect(bridge.channels.calls.single.channel, 'git');
  });

  testWidgets('non-git workspace renders no branch entry', (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => {
          'summary': {
            'branchName': null,
            'headRefType': 'branch',
            'isGitAvailable': false,
            'isRepository': false,
          }
        };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GitBranchChip(
          session: bridge,
          scope: const {'workspacePath': 'D:/NotRepo'},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('main'), findsNothing);
    expect(find.byType(GitBranchChip), findsOneWidget);
  });
}
