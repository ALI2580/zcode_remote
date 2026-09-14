import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/device_store.dart';

import '../ui/fake_features.dart';
import '../ui/fake_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('review: user and workspace plugin projections remain usable together',
      () async {
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FeatureBridge()));
    final bridge = FeatureBridge();
    const scope = {
      'workspaceIdentity': 'workspace',
      'workspacePath': 'D:/Synthetic'
    };
    try {
      final user = sessions.pluginCatalog('device', 'workspace', bridge, scope,
          selectedScope: 'user');
      final workspace = sessions.pluginCatalog(
          'device', 'workspace', bridge, scope,
          selectedScope: 'workspace');
      await user.refresh();
      await workspace.refresh();
      final lists = bridge.channels.calls
          .where((call) => call.method == 'listPlugins')
          .toList();
      expect(lists, hasLength(2),
          reason:
              'Opening the workspace projection must not dispose the user projection borrowed by Browser/Skills/Hooks.');
      expect(lists.map((call) => (call.args.single as Map)['configScope']),
          containsAll(['user', 'workspace']));
      expect(
          sessions.pluginCatalog('device', 'workspace', bridge, scope,
              selectedScope: 'user'),
          same(user));
      expect(
          sessions.pluginCatalog('device', 'workspace', bridge, scope,
              selectedScope: 'workspace'),
          same(workspace));
    } finally {
      sessions.dispose();
      await sessions.notifications.settled;
    }
  });
}
