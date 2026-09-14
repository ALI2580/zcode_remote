import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/device_store.dart';
import '../ui/fake_features.dart';
import '../ui/fake_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'review: shared plugin catalog follows bridge replacement in the same workspace',
      () async {
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FeatureBridge()));
    final first = FeatureBridge();
    final next = FeatureBridge();
    try {
      final original = sessions.pluginCatalog(
          'device', 'workspace', first, const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/Original'
      });
      final replaced = sessions.pluginCatalog(
          'device', 'workspace', next, const {
        'workspacePath': 'D:/Original',
        'workspaceIdentity': 'workspace'
      });
      expect(replaced.bridge, same(next),
          reason:
              'A reconnected bridge cannot receive the old catalog transport.');
      expect(replaced, isNot(same(original)));
      expect(
          sessions.pluginCatalog('device', 'workspace', next, const {
            'workspaceIdentity': 'workspace',
            'workspacePath': 'D:/Original'
          }),
          same(replaced),
          reason:
              'Equivalent scope maps should share one current catalog regardless of insertion order.');
    } finally {
      sessions.dispose();
      await sessions.notifications.settled;
    }
  });

  test('review: a renamed workspace path is reflected in the plugin RPC scope',
      () async {
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FeatureBridge()));
    final bridge = FeatureBridge();
    try {
      sessions.pluginCatalog('device', 'workspace', bridge, const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/Original'
      });
      final updated = sessions.pluginCatalog(
          'device', 'workspace', bridge, const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/Renamed'
      });
      await updated.refresh();
      final calls = bridge.channels.calls.where((call) =>
          call.method == 'listPlugins' || call.method == 'getPluginsOverview');
      expect(calls, hasLength(2));
      for (final call in calls) {
        expect((call.args.single as Map)['workspacePath'], 'D:/Renamed');
      }
    } finally {
      sessions.dispose();
      await sessions.notifications.settled;
    }
  });
}
