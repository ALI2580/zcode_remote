import 'package:flutter/material.dart';

import 'theme.dart';

/// Root application widget.
class ZcodeRemoteApp extends StatelessWidget {
  const ZcodeRemoteApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZcodeRemote',
      debugShowCheckedModeBanner: false,
      theme: ZInkTheme.light(),
      darkTheme: ZInkTheme.dark(),
      themeMode: ThemeMode.system,
      home: home,
    );
  }
}
