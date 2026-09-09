import 'package:flutter/material.dart';
import 'state/client_preferences.dart';

import 'state/device_store.dart';
import 'state/recovery_journal.dart';
import 'state/runtime_audit.dart';
import 'ui/app.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeAudit.initialize();
  final preferences = ClientPreferences();
  preferences.load();
  runApp(ZcodeRemoteApp(
      preferences: preferences,
      home: HomePage(
          store: DeviceStore(),
          preferences: preferences,
          recovery: RecoveryJournal.production())));
}
