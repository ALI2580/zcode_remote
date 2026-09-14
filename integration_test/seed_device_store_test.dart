import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/device_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seeds an encrypted runtime-injected device link',
      (tester) async {
    const url = String.fromEnvironment('ZCODE_SEED_DEVICE_URL');
    const label = String.fromEnvironment('ZCODE_SEED_DEVICE_LABEL');
    final store = DeviceStore();
    await store.addUrl(url, label: label.isEmpty ? null : label);
    expect(store.devices, hasLength(1));
    expect(store.devices.single.params, isNotNull);
  });
}
