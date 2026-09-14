import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/git_summary.dart';

import '../ui/fake_features.dart';

Map<String, dynamic> _summary() => {
      'workspacePath': 'D:/Synthetic',
      'repoRoot': 'D:/Synthetic',
      'branchName': 'main',
      'trackingBranchName': 'origin/main',
      'headRefType': 'branch',
      'ahead': 1,
      'behind': 2,
      'isDirty': true,
      'isGitAvailable': true,
      'isRepository': true,
    };

void main() {
  test('git summary refresh parses the official read-only summary', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'git');
      expect(method, 'refresh');
      final arg = args.single as Map;
      expect(arg['workspacePath'], 'D:/Synthetic');
      expect(arg['includeIdentity'], isFalse);
      expect(arg['includeBranchComparison'], isFalse);
      return {'summary': _summary()};
    };
    final controller = GitSummaryController(
      session: bridge,
      scope: const {
        'workspacePath': 'D:/Synthetic',
        'workspaceIdentity': 'synthetic',
      },
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.summary?.branchName, 'main');
    expect(controller.summary?.trackingBranchName, 'origin/main');
    expect(controller.summary?.ahead, 1);
    expect(controller.summary?.behind, 2);
    expect(controller.summary?.isDirty, isTrue);
    expect(bridge.channels.calls.map((call) => call.method), ['refresh']);
  });

  test('a failed refresh keeps the previous summary and reports the error',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => {'summary': _summary()};
    final controller = GitSummaryController(
      session: bridge,
      scope: const {'workspacePath': 'D:/Synthetic'},
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await controller.refresh();
    expect(controller.loading, isFalse);
    expect(controller.error, isA<StateError>());
    expect(controller.summary?.branchName, 'main');
  });
}
