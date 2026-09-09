import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';

const syntheticUrl =
    'https://zcode.z.ai/remote/v4?sid=synthetic-device&hash=synthetic-proof&t=1&mid=synthetic-machine';
Future<String?> encrypt(String plain) async =>
    'enc:${base64Encode(utf8.encode(plain))}';
Future<String?> decrypt(String encoded) async =>
    utf8.decode(base64Decode(encoded.substring(4)));
DeviceStore secureStore() =>
    DeviceStore(encrypt: encrypt, decrypt: decrypt, requireEncryption: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('WSS links remain usable and share secure-host identity with HTTPS',
      () async {
    final store = secureStore();
    final first =
        await store.addUrl(syntheticUrl.replaceFirst('https:', 'wss:'));
    expect(first.endpointOrigin, 'https://zcode.z.ai');
    final reloaded = secureStore();
    await reloaded.load();
    expect(reloaded.devices.single.params?.source.scheme, 'wss');
    final sameDevice = await reloaded.addUrl(syntheticUrl);
    expect(sameDevice.id, first.id);
    expect(reloaded.devices, hasLength(1));
  });
  test('encrypted persistence retains usable plaintext only in memory',
      () async {
    final store = secureStore();
    final device = await store.addUrl(syntheticUrl);
    expect(device.params?.deviceSid, 'synthetic-device');
    final persisted = (await SharedPreferences.getInstance())
        .getString(DeviceStore.prefsKey)!;
    expect(persisted, isNot(contains('synthetic-proof')));
    expect(persisted, isNot(contains('synthetic-device')));
    final reloaded = secureStore();
    await reloaded.load();
    expect(reloaded.devices.single.url, syntheticUrl);
    expect(reloaded.devices.single.id, device.id);
  });
  test(
      'Android encryption failure never falls back to plaintext or commits a device',
      () async {
    final store =
        DeviceStore(encrypt: (_) async => null, requireEncryption: true);
    await expectLater(store.addUrl(syntheticUrl), throwsStateError);
    expect(store.devices, isEmpty);
    expect(
        (await SharedPreferences.getInstance()).getString(DeviceStore.prefsKey),
        isNull);
  });
  test('legacy pairing id migrates to a stable local id and encrypted record',
      () async {
    SharedPreferences.setMockInitialValues({
      DeviceStore.prefsKey: jsonEncode([
        {
          'id': 'synthetic-device',
          'label': '原设备',
          'url': syntheticUrl,
          'addedAt': 1,
          'lastUsedAt': 1,
        }
      ])
    });
    final store = secureStore();
    await store.load();
    expect(store.devices.single.id, isNot('synthetic-device'));
    final reloaded = secureStore();
    await reloaded.load();
    expect(reloaded.devices.single.id, store.devices.single.id);
    expect(reloaded.devices.single.label, '原设备');
  });
  test('credential rotation on same machine preserves local identity',
      () async {
    final store = secureStore();
    final first = await store.addUrl(syntheticUrl, label: '工作电脑');
    final changed = await store.addUrl(syntheticUrl
        .replaceFirst('sid=synthetic-device', 'sid=rotated')
        .replaceFirst('synthetic-proof', 'new-proof'));
    expect(changed.id, first.id);
    expect(changed.label, first.label);
    expect(changed.params?.passHash, 'new-proof');
    expect(store.devices, hasLength(1));
  });
  test('concurrent mutations preserve both devices and their credentials',
      () async {
    final store = secureStore();
    await Future.wait([
      store.addUrl(syntheticUrl),
      store.addUrl(syntheticUrl
          .replaceFirst('synthetic-machine', 'machine-B')
          .replaceFirst('synthetic-device', 'device-B')),
    ]);
    final reloaded = secureStore();
    await reloaded.load();
    expect(reloaded.devices, hasLength(2));
    expect(reloaded.devices.every((device) => device.params != null), isTrue);
  });
}
