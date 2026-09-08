import 'package:flutter/material.dart';

import 'state/device_store.dart';
import 'ui/app.dart';
import 'ui/home_page.dart';

void main() {
  runApp(ZcodeRemoteApp(home: HomePage(store: DeviceStore())));
}
