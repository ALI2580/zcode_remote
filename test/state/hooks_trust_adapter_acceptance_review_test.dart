import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import '../support/review_channel_bridge.dart';

void main() {
  WorkspaceHook hook({String identity = 'workspace'}) => WorkspaceHook.fromRaw({
        'id': 'hook-trust',
        'event': 'PreToolUse',
        'type': 'command',
        'command': 'synthetic',
        'enabled': true,
        'location': {'source': 'zcode', 'scope': 'project'},
        'workspaceHook': {
          'trustState': 'pending_trust',
          'workspaceIdentity': identity,
          'bundleDigest': 'bundle-digest',
          'hookDeclarationDigest': 'hook-digest',
          'reviewItemId': 'review-item',
        },
      });

  test('trust adapter sends only the confirmed workspace identity and digests',
      () async {
    final bridge = ReviewChannelBridge();
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) {
      calls.add((channel, method, args));
      return {'accepted': true};
    };
    final catalog = HooksCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Synthetic',
    );
    addTearDown(catalog.dispose);

    final result = await catalog.grantWorkspaceHookTrust(hook());
    expect(result['accepted'], isTrue);
    final call =
        calls.singleWhere((entry) => entry.$2 == 'grantWorkspaceHookTrust');
    expect(call.$1, Channels.hooks);
    expect((call.$3.single as Map).cast<String, dynamic>(), {
      'workspaceIdentity': 'workspace',
      'workspacePath': 'D:/Synthetic',
      'bundleDigest': 'bundle-digest',
      'hookDeclarationDigest': 'hook-digest',
    });
  });

  test('identity or digest mismatch is rejected locally without an RPC',
      () async {
    final bridge = ReviewChannelBridge();
    var calls = 0;
    bridge.channels.handler = (_, __, ___) {
      calls++;
      return {'accepted': true};
    };
    final catalog = HooksCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Synthetic',
    );
    addTearDown(catalog.dispose);

    final result = await catalog.grantWorkspaceHookTrust(
      hook(identity: 'other'),
    );
    expect(result, {
      'accepted': false,
      'reasonCode': 'workspace_hooks_snapshot_mismatch',
    });
    expect(calls, 0);
  });

  test('accepted false and unknown responses remain visible failures',
      () async {
    final bridge = ReviewChannelBridge();
    var response = <String, dynamic>{
      'accepted': false,
      'reasonCode': 'workspace_hooks_bundle_changed',
    };
    bridge.channels.handler = (_, __, ___) => response;
    final catalog = HooksCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Synthetic',
    );
    addTearDown(catalog.dispose);

    expect(
      (await catalog.grantWorkspaceHookTrust(hook()))['reasonCode'],
      'workspace_hooks_bundle_changed',
    );
    response = <String, dynamic>{'status': 'accepted'};
    expect(
      (await catalog.grantWorkspaceHookTrust(hook()))['accepted'],
      isFalse,
    );
  });
}
