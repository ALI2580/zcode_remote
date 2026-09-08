import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zcode_remote/state/device_store.dart';

void main() {
  const url = 'https://zcode.z.ai/remote/v4?sid=abc123&hash=xyz&t=1700000000&mid=m1&name=Desktop';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('adds a device from a valid URL', () async {
    final store = DeviceStore();
    await store.load();
    final device = await store.addUrl(url, label: '我的桌面');

    expect(device.label, '我的桌面');
    expect(device.id, 'abc123');
    expect(device.params?.deviceSid, 'abc123');
    expect(store.devices, hasLength(1));
  });

  test('rejects an invalid URL', () async {
    final store = DeviceStore();
    await store.load();
    expect(() => store.addUrl('not-a-url'), throwsFormatException);
    expect(store.devices, isEmpty);
  });

  test('persists across reloads', () async {
    final store = DeviceStore();
    await store.load();
    await store.addUrl(url, label: 'A');
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=def456&hash=xyz&t=1700000000',
        label: 'B');

    final reloaded = DeviceStore();
    await reloaded.load();
    expect(reloaded.devices, hasLength(2));
    expect(reloaded.devices.map((d) => d.label), containsAll(['A', 'B']));
  });

  test('re-adding the same sid keeps label and storage count', () async {
    final store = DeviceStore();
    await store.load();
    await store.addUrl(url, label: '原名');
    await store.addUrl(url, label: '新名');

    expect(store.devices, hasLength(1));
    expect(store.devices.single.label, '新名');
  });

  test('rename and remove', () async {
    final store = DeviceStore();
    await store.load();
    final device = await store.addUrl(url);
    await store.rename(device.id, '改名后');
    expect(store.devices.single.label, '改名后');

    await store.remove(device.id);
    expect(store.devices, isEmpty);
  });

  test('lastUsed picks the most recently touched device', () async {
    final store = DeviceStore();
    await store.load();
    final a = await store.addUrl(url, label: 'A');
    final b = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=def456&hash=xyz&t=1700000000',
        label: 'B');

    expect(store.lastUsed?.id, b.id);
    await store.touch(a.id);
    expect(store.lastUsed?.id, a.id);
  });
}
