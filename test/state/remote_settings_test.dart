import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_settings.dart';

import '../ui/fake_features.dart';

Map<String, dynamic> _settings() => {
      'providerFamilyDomain': 'zai',
      'modelProviderFamilyModes': {'zai': 'oauth'},
      'modelProviderFamilySelectedKeys': {
        'zai': 'coding-plan:builtin:zai-start-plan'
      },
      'askUserQuestionAutoResolutionEnabled': false,
      'memoryEnabled': true,
      'taskAutoArchiveEnabled': true,
      'taskAutoArchiveOlderThanDays': 30,
    };

void main() {
  test('general-page fields parse including the nested integrated shell', () {
    final snapshot = RemoteSettingsSnapshot.fromRaw({
      'terminalInheritSystemProfile': false,
      'terminalFontFamily': 'Cascadia Mono',
      'integratedTerminalShell': {
        'mode': 'shell',
        'id': 'git-bash',
        'label': 'Git Bash',
        'dialect': 'bash',
        'path': 'D:/Git/bin/bash.exe',
      },
      'nativeSearchEnhancementsEnabled': false,
      'httpProxy': 'http://127.0.0.1:7890',
      'httpProxyNoProxy': 'localhost,.internal.com',
      'httpProxyCaCertPath': 'D:/certs/ca.pem',
      'toolGroupingExploreEnabled': true,
      'toolGroupingTerminalEnabled': false,
      'toolGroupingChangesEnabled': true,
    });
    expect(snapshot.terminalInheritSystemProfile, isFalse);
    expect(snapshot.terminalFontFamily, 'Cascadia Mono');
    expect(snapshot.integratedTerminalShellMode, 'shell');
    expect(snapshot.integratedTerminalShellId, 'git-bash');
    expect(snapshot.integratedTerminalShellLabel, 'Git Bash');
    expect(snapshot.integratedTerminalShellDialect, 'bash');
    expect(snapshot.integratedTerminalShellPath, 'D:/Git/bin/bash.exe');
    expect(snapshot.nativeSearchEnhancementsEnabled, isFalse);
    expect(snapshot.httpProxy, 'http://127.0.0.1:7890');
    expect(snapshot.httpProxyNoProxy, 'localhost,.internal.com');
    expect(snapshot.httpProxyCaCertPath, 'D:/certs/ca.pem');
    expect(snapshot.toolGroupingExploreEnabled, isTrue);
    expect(snapshot.toolGroupingTerminalEnabled, isFalse);
    expect(snapshot.toolGroupingChangesEnabled, isTrue);

    // Missing keys stay unknown so the UI can apply official defaults
    // without conflating them with stored values; a non-map shell is not
    // silently coerced into the auto mode.
    final empty = RemoteSettingsSnapshot.fromRaw(const {
      'integratedTerminalShell': 'auto',
    });
    expect(empty.terminalInheritSystemProfile, isNull);
    expect(empty.nativeSearchEnhancementsEnabled, isNull);
    expect(empty.integratedTerminalShellMode, isNull);
    expect(empty.integratedTerminalShellId, isNull);
  });

  test('remote settings refresh reads the official setting service', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'setting');
      expect(method, 'get');
      expect(args, isEmpty);
      return _settings();
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.status, RemoteSettingsStatus.loaded);
    expect(controller.error, isNull);
    expect(controller.snapshot.providerFamilyDomain, 'zai');
    expect(controller.snapshot.providerFamilyModes['zai'], 'oauth');
    expect(controller.snapshot.providerFamilySelectedKeys['zai'],
        'coding-plan:builtin:zai-start-plan');
    expect(controller.snapshot.askUserQuestionAutoResolutionEnabled, isFalse);
    expect(controller.snapshot.taskAutoArchiveOlderThanDays, 30);
    expect(bridge.channels.calls.map((call) => call.channel), ['setting']);
  });

  test('a failed refresh keeps the previous snapshot and supports retry',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => _settings();
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);
    await controller.refresh();

    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await controller.refresh();
    expect(controller.status, RemoteSettingsStatus.error);
    expect(controller.error, isA<StateError>());
    expect(controller.snapshot.providerFamilyDomain, 'zai');

    bridge.channels.handler = (_, __, ___) => _settings();
    await controller.refresh();
    expect(controller.status, RemoteSettingsStatus.loaded);
    expect(controller.error, isNull);
  });

  test('a stale response cannot replace a newer scoped controller', () async {
    final bridge = FeatureBridge();
    final gate = Completer<Object?>();
    bridge.channels.handler = (_, __, ___) => gate.future;
    final old = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    final ignored = old.refresh();
    old.dispose();

    bridge.channels.handler = (_, __, ___) => _settings();
    final fresh = RemoteSettingsController(
        session: bridge, scopeKey: 'device-2|workspace-2');
    addTearDown(fresh.dispose);
    await fresh.refresh();
    expect(fresh.snapshot.memoryEnabled, isTrue);

    gate.complete(_settings());
    await ignored;
    expect(old.snapshot.isEmpty, isTrue);
    expect(fresh.status, RemoteSettingsStatus.loaded);
  });

  test('update sends the official patch and renders the read-back value',
      () async {
    final bridge = FeatureBridge();
    var autoResolve = false;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        expect(channel, 'setting');
        expect(args, [
          {'askUserQuestionAutoResolutionEnabled': true},
        ]);
        autoResolve = true;
        return null;
      }
      expect(method, 'get');
      return _settings()
        ..['askUserQuestionAutoResolutionEnabled'] = autoResolve;
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.snapshot.askUserQuestionAutoResolutionEnabled, isFalse);
    await controller.update('askUserQuestionAutoResolutionEnabled', true);
    expect(controller.isSaving('askUserQuestionAutoResolutionEnabled'),
        isFalse);
    expect(controller.saveError('askUserQuestionAutoResolutionEnabled'),
        isNull);
    expect(controller.snapshot.askUserQuestionAutoResolutionEnabled, isTrue);
  });

  test('a failed update keeps the previous snapshot and retry succeeds',
      () async {
    final bridge = FeatureBridge();
    var fail = true;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        if (fail) throw StateError('rejected');
        return null;
      }
      return _settings();
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.update('askUserQuestionAutoResolutionEnabled', true);
    expect(controller.snapshot.askUserQuestionAutoResolutionEnabled, isFalse);
    expect(controller.saveError('askUserQuestionAutoResolutionEnabled'),
        isA<StateError>());

    fail = false;
    await controller.update('askUserQuestionAutoResolutionEnabled', true);
    expect(controller.saveError('askUserQuestionAutoResolutionEnabled'),
        isNull);
  });

  test('a duplicate update for the same key is ignored while saving',
      () async {
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    var updateCalls = 0;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        updateCalls++;
        return updateCalls == 1 ? gate.future : null;
      }
      return _settings();
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);
    await controller.refresh();

    final first = controller.update('askUserQuestionAutoResolutionEnabled', true);
    await Future<void>.delayed(Duration.zero);
    await controller.update('askUserQuestionAutoResolutionEnabled', false);
    expect(updateCalls, 1);
    gate.complete();
    await first;
    expect(controller.isSaving('askUserQuestionAutoResolutionEnabled'),
        isFalse);
  });

  test('updatePatch sends multi-key patches and reads back', () async {
    final bridge = FeatureBridge();
    final patches = <Map<String, dynamic>>[];
    var repoEnabled = false;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        patches.add(patch);
        repoEnabled = patch['repoSnapshotIndexingEnabled'] as bool;
        return null;
      }
      return _settings()..['repoSnapshotIndexingEnabled'] = repoEnabled;
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);
    await controller.refresh();

    const patch = {
      'repoSnapshotIndexingEnabled': true,
      'repoSnapshotIndexingUserConfigured': true,
    };
    await controller.updatePatch(patch);
    expect(patches.single, patch);
    expect(controller.snapshot.repoSnapshotIndexingEnabled, isTrue);
    expect(controller.saveError(
        'repoSnapshotIndexingEnabled|repoSnapshotIndexingUserConfigured'),
        isNull);
  });

  test('a failed multi-key patch keeps the snapshot and retries as a whole',
      () async {
    final bridge = FeatureBridge();
    var fail = true;
    var repoEnabled = false;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        if (fail) throw StateError('rejected');
        repoEnabled =
            (args.single as Map)['repoSnapshotIndexingEnabled'] as bool;
        return null;
      }
      return _settings()..['repoSnapshotIndexingEnabled'] = repoEnabled;
    };
    final controller = RemoteSettingsController(
        session: bridge, scopeKey: 'device-1|workspace-1');
    addTearDown(controller.dispose);
    await controller.refresh();

    const patch = {
      'repoSnapshotIndexingEnabled': true,
      'repoSnapshotIndexingUserConfigured': true,
    };
    await controller.updatePatch(patch);
    expect(controller.snapshot.repoSnapshotIndexingEnabled, isFalse);

    fail = false;
    await controller.updatePatch(
        (controller.lastAttempt(
                'repoSnapshotIndexingEnabled|repoSnapshotIndexingUserConfigured')
            as Map).cast<String, Object?>());
    expect(controller.snapshot.repoSnapshotIndexingEnabled, isTrue);
  });

  test('a just-reset oauth key upgrades to the bound team key', () async {
    final bridge = FeatureBridge();
    var selectedKeys = <String, String>{
      'zai': 'legacy:zai-key',
    };
    final updates = <Map<String, dynamic>>[];
    var pricingCalls = 0;
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'coding-plan-subscription') {
        expect(method, 'getEnterprisePricing');
        expect((args.single as Map)['authenticated'], isTrue);
        expect((args.single as Map)['family'], 'zai');
        pricingCalls++;
        return {
          'productList': [
            {'subscribed': false, 'productId': 'p0'},
            {
              'subscribed': true,
              'productId': 'p1',
              'teamProjects': [
                {'organizationId': ' org ', 'projectId': 'prj'},
              ],
            },
          ],
        };
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        updates.add(patch);
        selectedKeys =
            (patch['modelProviderFamilySelectedKeys'] as Map)
                .cast<String, String>();
        return null;
      }
      return _settings()
        ..['modelProviderFamilyModes'] = {'zai': 'oauth'}
        ..['modelProviderFamilySelectedKeys'] = selectedKeys;
    };

    expect(
        await migrateProviderFamilySelections(
            session: bridge, upgradeTeamPlan: true),
        ['zai']);
    expect(pricingCalls, 1);
    expect(updates, hasLength(2));
    expect(updates[0]['modelProviderFamilySelectedKeys']['zai'],
        'coding-plan:builtin:zai-coding-plan');
    expect(updates[1]['modelProviderFamilySelectedKeys']['zai'],
        'team-plan:builtin:zai-coding-plan:p1:org:prj');
  });

  test('invalid keys reset to the mode default without an upgrade', () async {
    final bridge = FeatureBridge();
    var selectedKeys = <String, String>{'zai': 'legacy:zai-key'};
    final updates = <Map<String, dynamic>>[];
    var pricingCalls = 0;
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'coding-plan-subscription') {
        pricingCalls++;
        return {'productList': <Map>[]};
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        updates.add(patch);
        selectedKeys =
            (patch['modelProviderFamilySelectedKeys'] as Map)
                .cast<String, String>();
        return null;
      }
      return _settings()
        ..['modelProviderFamilyModes'] = {'zai': 'oauth'}
        ..['modelProviderFamilySelectedKeys'] = selectedKeys;
    };

    expect(
        await migrateProviderFamilySelections(
            session: bridge, upgradeTeamPlan: false),
        ['zai']);
    expect(pricingCalls, 0);
    expect(updates, hasLength(1));
    expect(updates.single['modelProviderFamilySelectedKeys']['zai'],
        'coding-plan:builtin:zai-coding-plan');
  });

  test('apiKey modes reset to the preset key', () async {
    final bridge = FeatureBridge();
    var selectedKeys = <String, String>{};
    final updates = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'coding-plan-subscription') {
        throw StateError('apiKey modes must not read team pricing');
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        updates.add(patch);
        selectedKeys =
            (patch['modelProviderFamilySelectedKeys'] as Map)
                .cast<String, String>();
        return null;
      }
      return _settings()
        ..['modelProviderFamilyModes'] = {'zai': 'apiKey'}
        ..['modelProviderFamilySelectedKeys'] = selectedKeys;
    };

    expect(
        await migrateProviderFamilySelections(
            session: bridge, upgradeTeamPlan: true),
        ['zai']);
    expect(updates.single['modelProviderFamilySelectedKeys']['zai'],
        'preset:builtin:zai');
  });

  test('valid keys are never rewritten, even with upgrade allowed', () async {
    for (final validKey in [
      'coding-plan:builtin:zai-coding-plan',
      'coding-plan:builtin:zai-start-plan',
      'team-plan:builtin:zai-coding-plan:p1:org:prj',
    ]) {
      final bridge = FeatureBridge();
      var updates = 0;
      var pricingCalls = 0;
      bridge.channels.handler = (channel, method, args) {
        if (channel == 'coding-plan-subscription') {
          pricingCalls++;
          return {'productList': <Map>[]};
        }
        if (method == 'update') updates++;
        return _settings()
          ..['modelProviderFamilyModes'] = {'zai': 'oauth'}
          ..['modelProviderFamilySelectedKeys'] = {'zai': validKey};
      };

      expect(
          await migrateProviderFamilySelections(
              session: bridge, upgradeTeamPlan: true),
          isEmpty);
      expect(updates, 0, reason: validKey);
      expect(pricingCalls, 0, reason: validKey);
    }
  });

  test('unavailable keys and empty identities keep the reset default',
      () async {
    final bridge = FeatureBridge();
    var selectedKeys = <String, String>{'zai': 'legacy:zai-key'};
    final updates = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'coding-plan-subscription') {
        return {
          'productList': [
            {
              'subscribed': true,
              'productId': 'p1',
              'teamProjects': [
                {'organizationId': 'org', 'projectId': 'prj', 'apiKeyStatus': 'unavailable'},
                {'organizationId': '', 'projectId': 'prj'},
              ],
            },
          ],
        };
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        updates.add(patch);
        selectedKeys =
            (patch['modelProviderFamilySelectedKeys'] as Map)
                .cast<String, String>();
        return null;
      }
      return _settings()
        ..['modelProviderFamilyModes'] = {'zai': 'oauth'}
        ..['modelProviderFamilySelectedKeys'] = selectedKeys;
    };

    expect(
        await migrateProviderFamilySelections(
            session: bridge, upgradeTeamPlan: true),
        ['zai']);
    expect(updates, hasLength(1));
    expect(updates.single['modelProviderFamilySelectedKeys']['zai'],
        'coding-plan:builtin:zai-coding-plan');
  });

  test('unset family modes never migrate', () async {
    final bridge = FeatureBridge();
    var updates = 0;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') updates++;
      return _settings()
        ..['modelProviderFamilyModes'] = <String, String>{}
        ..['modelProviderFamilySelectedKeys'] = <String, String>{};
    };

    expect(
        await migrateProviderFamilySelections(
            session: bridge, upgradeTeamPlan: true),
        isEmpty);
    expect(updates, 0);
  });
}
