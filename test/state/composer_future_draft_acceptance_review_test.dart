import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/device_store.dart';
import '../ui/fake_features.dart';
import '../ui/fake_workspace.dart';

class _CachedBridge extends FakeBridge {
  @override
  final FeatureChannels channels = FeatureChannels();
  late final cached = ConversationTransport(
      session: this, scope: const {'workspaceIdentity': 'workspace'});
  @override
  ConversationTransport conversation(Map<String, dynamic> scope,
          {void Function(String)? onLog}) =>
      cached;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'review: settings refresh also invalidates cached prep before any composer exists',
      () async {
    final bridge = _CachedBridge();
    var label = 'Before settings save';
    bridge.channels.handler = (_, method, __) => method == 'prepareWorkspace'
        ? {
            'configOptions': [
              {
                'id': 'model',
                'category': 'model',
                'type': 'select',
                'currentValue': 'review/model',
                'options': [
                  {
                    'value': 'review/model',
                    'name': label,
                    'modelProviderId': 'review',
                    'modelProviderName': 'Review'
                  }
                ]
              }
            ]
          }
        : {};
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        source: const WorkspaceTaskSource(
            deviceId: 'd', deviceLabel: 'D', workspaceKey: 'workspace'),
        notifications: sessions.notifications);
    try {
      await bridge.cached.prepareWorkspace();
      label = 'After settings save';
      await sessions.refreshComposerScopeForMonitor(monitor);
      final newDraft = sessions.composers.obtain(
          transport: bridge.cached, deviceId: 'd', workspaceKey: 'workspace');
      await newDraft.loadOptions();
      expect(newDraft.options.models.single.name, 'After settings save',
          reason:
              'A future draft must not reuse metadata cached before the settings write.');
    } finally {
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
    }
  });
}
