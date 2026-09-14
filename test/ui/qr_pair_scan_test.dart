import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/qr_pairing.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/device_directory.dart';
import 'package:zcode_remote/ui/qr_scan_page.dart';

import 'fake_workspace.dart';

final _link = Uri.parse('https://zcode.z.ai/remote/v4').replace(queryParameters: {
  'sid': 'sid-scan',
  'hash': 'aGFzaA==',
  't': '1000',
  'mid': 'machine-1',
  'name': 'ALI',
}).toString();

Widget _harness(DeviceStore store, FakeAppSessions sessions) => MaterialApp(
    localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
    home: Scaffold(
        body: DeviceDirectory(
            store: store,
            sessions: sessions,
            onOpen: (_) async {},
            onSettings: () {})));

FakeAppSessions _sessions(DeviceStore store) => FakeAppSessions(
    store: store,
    sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));

DeviceStore _store() {
  // Host tests default to TargetPlatform.android, so the real
  // CredentialCipher would send the zcode_remote/crypto channel into the
  // never-drained test buffers. Use identity codecs instead.
  return DeviceStore(
      requireEncryption: false,
      encrypt: (value) async => value,
      decrypt: (value) async => value);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('sanitizeRemoteControlPayload', () {
    test('strips whitespace, BOM, quotes and angle brackets', () {
      expect(sanitizeRemoteControlPayload('  $_link \n'), _link);
      expect(sanitizeRemoteControlPayload('\ufeff"$_link"'), _link);
      expect(sanitizeRemoteControlPayload('<$_link>'), _link);
      expect(sanitizeRemoteControlPayload("'$_link'"), _link);
    });

    test('rejects non-remote-control payloads', () {
      expect(sanitizeRemoteControlPayload(''), isNull);
      expect(sanitizeRemoteControlPayload('https://example.com/a=b'), isNull);
      expect(
          sanitizeRemoteControlPayload(
              'https://zcode.z.ai/remote/v4?hash=x&t=1'),
          isNull);
    });
  });

  testWidgets('scan fills the add dialog and saves a new device',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final previousLauncher = qrScanLauncher;
      qrScanLauncher = (_) async => '  $_link \n';
      addTearDown(() => qrScanLauncher = previousLauncher);
      final store = _store();
      await store.load();
      final sessions = _sessions(store);
      addTearDown(sessions.dispose);

      await tester.pumpWidget(_harness(store, sessions));
      await tester.tap(find.byTooltip('Add device'));
      await tester.pumpAndSettle();

      expect(find.text('Add device'), findsOneWidget);
      await tester.tap(find.byTooltip('Scan QR code').last);
      await tester.pumpAndSettle();

      expect(find.text('The QR code is not a valid remote-control link'),
          findsNothing);
      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Remote-control link'));
      expect(field.controller!.text, _link);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(store.devices.single.params!.deviceSid, 'sid-scan');
      expect(store.devices.single.machineId, 'machine-1');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('scan updates an expired device link in place', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final previousLauncher = qrScanLauncher;
      qrScanLauncher = (_) async => _link;
      addTearDown(() => qrScanLauncher = previousLauncher);
      final store = _store();
      await store.load();
      final stale = Uri.parse('https://zcode.z.ai/remote/v4')
          .replace(queryParameters: {
        'sid': 'sid-expired',
        'hash': 'b2xk',
        't': '1',
        'mid': 'machine-1',
        'name': 'ALI',
      }).toString();
      final device = await store.addUrl(stale, label: 'ALI');
      final sessions = _sessions(store);
      addTearDown(sessions.dispose);

      await tester.pumpWidget(_harness(store, sessions));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update connection link'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan QR code').last);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Remote-control link'));
      expect(field.controller!.text, _link);

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      final updated = store.devices.single;
      expect(updated.id, device.id);
      expect(updated.params!.deviceSid, 'sid-scan');
      expect(store.devices, hasLength(1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('invalid QR payload surfaces an error and keeps the dialog',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final previousLauncher = qrScanLauncher;
      qrScanLauncher = (_) async => 'https://example.com/not-a-pairing';
      addTearDown(() => qrScanLauncher = previousLauncher);
      final store = _store();
      await store.load();
      final sessions = _sessions(store);
      addTearDown(sessions.dispose);

      await tester.pumpWidget(_harness(store, sessions));
      await tester.tap(find.byTooltip('Add device'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan QR code').last);
      await tester.pumpAndSettle();

      expect(find.text('The QR code is not a valid remote-control link'),
          findsOneWidget);
      expect(find.text('Add device'), findsOneWidget);
      expect(store.devices, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
