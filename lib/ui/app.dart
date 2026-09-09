import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../state/client_preferences.dart';
import '../state/runtime_audit.dart';

import 'theme.dart';

/// Root application widget.
class ZcodeRemoteApp extends StatelessWidget {
  const ZcodeRemoteApp({super.key, required this.home, this.preferences});

  final Widget home;
  final ClientPreferences? preferences;

  @override
  Widget build(BuildContext context) {
    final prefs = preferences;
    if (prefs == null) return _app(null);
    return ClientPreferencesScope(
        preferences: prefs,
        child: ListenableBuilder(
            listenable: prefs, builder: (_, __) => _app(prefs)));
  }

  Widget _app(ClientPreferences? prefs) {
    return MaterialApp(
      title: 'ZcodeRemote',
      debugShowCheckedModeBanner: false,
      theme: ZInkTheme.light(),
      darkTheme: ZInkTheme.dark(),
      themeMode: prefs?.theme ?? ThemeMode.system,
      locale: prefs?.locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
            data: media.copyWith(
                textScaler:
                    ClientTextScaler(media.textScaler, prefs?.textScale ?? 1)),
            child: RuntimeAudit.quotaReadOnly
                ? Banner(
                    message: '额度只读验收',
                    location: BannerLocation.topEnd,
                    child: child!)
                : child!);
      },
      home: home,
    );
  }
}
