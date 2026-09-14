import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientPreferences extends ChangeNotifier {
  static const storageKey = 'zcode_remote_client_preferences_v1';
  static const codeThemeIds = <String>[
    'github-light',
    'github-dark',
    'vitesse-light',
    'vitesse-dark',
    'min-light',
    'min-dark',
    'github-light-high-contrast',
    'github-dark-high-contrast',
    'catppuccin-latte',
    'catppuccin-mocha',
  ];
  static const codeThemeLabels = <String, String>{
    'github-light': 'GitHub Light',
    'github-dark': 'GitHub Dark',
    'vitesse-light': 'Vitesse Light',
    'vitesse-dark': 'Vitesse Dark',
    'min-light': 'Minimal Light',
    'min-dark': 'Minimal Dark',
    'github-light-high-contrast': 'GitHub HC Light',
    'github-dark-high-contrast': 'GitHub HC Dark',
    'catppuccin-latte': 'Catppuccin Latte',
    'catppuccin-mocha': 'Catppuccin Mocha',
  };
  ThemeMode _theme = ThemeMode.system;
  String _language = 'system';
  double _textScale = 1;
  int _uiFontSizePx = 14;
  double _codeFontSize = 12;
  String _taskView = 'project';
  String _taskSort = 'updated';
  // Official appearance page code settings (xQt): client-local preview
  // preferences, GitHub Light/Dark defaults, line numbers on, wrap off.
  String _lightCodeTheme = 'github-light';
  String _darkCodeTheme = 'github-dark';
  bool _showLineNumbers = true;
  bool _wrapLongLines = false;
  // Official `zcode:sidebar-usage-coding-plan-provider` localStorage
  // preference: the usage statistics page's Coding Plan source, validated
  // against the official `o2e`/`s2e` rules on read.
  String? _usagePlanSource;
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  ThemeMode get theme => _theme;
  String get language => _language;
  double get textScale => _textScale;
  int get uiFontSizePx => _uiFontSizePx;
  double get uiFontScale => _uiFontSizePx / 14;
  double get codeFontSize => _codeFontSize;
  String get taskView => _taskView;
  String get taskSort => _taskSort;
  /// Label compatibility for the pre-U16 Settings page. New consumers should
  /// use the stable ID getters; persistence always stores the IDs.
  String get lightCodeTheme => codeThemeLabels[_lightCodeTheme] ?? 'GitHub Light';
  String get darkCodeTheme => codeThemeLabels[_darkCodeTheme] ?? 'GitHub Dark';
  String get lightCodeThemeId => _lightCodeTheme;
  String get darkCodeThemeId => _darkCodeTheme;
  bool get showLineNumbers => _showLineNumbers;
  bool get wrapLongLines => _wrapLongLines;
  String? get usagePlanSource => _usagePlanSource;
  bool get loaded => _loaded;
  Locale? get locale => switch (_language) {
        'zh' => const Locale('zh', 'CN'),
        'en' => const Locale('en', 'US'),
        _ => null,
      };
  Future<void> get settled => _writes;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString(storageKey) ?? '{}');
      if (raw is Map) {
        _theme = ThemeMode.values
                .where((mode) => mode.name == raw['theme'])
                .firstOrNull ??
            ThemeMode.system;
        _language = ['system', 'zh', 'en'].contains(raw['language'])
            ? raw['language'] as String
            : 'system';
        final legacyScale = _bounded(raw['textScale'], .8, 1.4, 1);
        _uiFontSizePx = _boundedInt(
            raw['uiFontSizePx'], 12, 20, (legacyScale * 14).round());
        // Keep the legacy factor readable for existing QA and callers while
        // using the integer px value for the actual app scaler.
        _textScale = raw['textScale'] is num &&
                (raw['textScale'] as num).isFinite
            ? legacyScale
            : uiFontScale;
        _codeFontSize = _bounded(
                raw['codeFontSize'], 12, 20, 12)
            .roundToDouble();
        _taskView = raw['taskView'] == 'timeline' ? 'timeline' : 'project';
        _taskSort = raw['taskSort'] == 'created' ? 'created' : 'updated';
        _lightCodeTheme = _themeId(raw['lightCodeTheme'], 'github-light');
        _darkCodeTheme = _themeId(raw['darkCodeTheme'], 'github-dark');
        _showLineNumbers = raw['showLineNumbers'] is bool
            ? raw['showLineNumbers'] as bool
            : _showLineNumbers;
        _wrapLongLines = raw['wrapLongLines'] is bool
            ? raw['wrapLongLines'] as bool
            : _wrapLongLines;
        _usagePlanSource =
            raw['usagePlanSource'] is String ? raw['usagePlanSource'] as String : null;
      }
    } catch (_) {
      /* Keep readable defaults for a corrupted preference record. */
    }
    _loaded = true;
    notifyListeners();
  }

  double _bounded(dynamic value, double low, double high, double fallback) =>
      value is num && value.isFinite
          ? value.toDouble().clamp(low, high)
          : fallback;
  int _boundedInt(dynamic value, int low, int high, int fallback) {
    final candidate = value is num && value.isFinite ? value.round() : fallback;
    return candidate.clamp(low, high);
  }

  String _themeId(dynamic value, String fallback) {
    if (value is! String) return fallback;
    if (codeThemeIds.contains(value)) return value;
    for (final entry in codeThemeLabels.entries) {
      if (entry.value == value) return entry.key;
    }
    return fallback;
  }
  Future<void> setTheme(ThemeMode value) async {
    await load();
    _theme = value;
    await _save();
  }

  Future<void> setLanguage(String value) async {
    await load();
    if (!['system', 'zh', 'en'].contains(value)) return;
    _language = value;
    await _save();
  }

  Future<void> setTextScale(num value) async {
    await load();
    _textScale = _bounded(value, .8, 1.4, 1);
    _uiFontSizePx = _boundedInt((_textScale * 14).round(), 12, 20, 14);
    await _save();
  }

  Future<void> setUiFontSizePx(num value) async {
    await load();
    _uiFontSizePx = _boundedInt(value, 12, 20, 14);
    // Keep the legacy factor inside its historical 0.8–1.4 contract. The
    // integer px value is the authoritative U16 UI setting for the app root.
    _textScale = _bounded(_uiFontSizePx / 14, .8, 1.4, 1);
    await _save();
  }

  Future<void> setCodeFontSize(num value) async {
    await load();
    _codeFontSize = _bounded(value, 12, 20, 12).roundToDouble();
    await _save();
  }

  Future<void> resetAppearance() async {
    await load();
    _theme = ThemeMode.system;
    _uiFontSizePx = 14;
    _textScale = 1;
    _codeFontSize = 12;
    _lightCodeTheme = 'github-light';
    _darkCodeTheme = 'github-dark';
    _showLineNumbers = true;
    _wrapLongLines = false;
    await _save();
  }

  Future<void> setLightCodeTheme(String value) async {
    await load();
    final id = _themeId(value, _lightCodeTheme);
    if (!codeThemeIds.contains(id)) return;
    _lightCodeTheme = id;
    await _save();
  }

  Future<void> setDarkCodeTheme(String value) async {
    await load();
    final id = _themeId(value, _darkCodeTheme);
    if (!codeThemeIds.contains(id)) return;
    _darkCodeTheme = id;
    await _save();
  }

  Future<void> setShowLineNumbers(bool value) async {
    await load();
    _showLineNumbers = value;
    await _save();
  }

  Future<void> setWrapLongLines(bool value) async {
    await load();
    _wrapLongLines = value;
    await _save();
  }

  /// Official `l2e` — persist the sidebar usage Coding Plan source. Callers
  /// must validate with `UsagePlanSelection.isValidPreference` first.
  Future<void> setUsagePlanSource(String value) async {
    await load();
    _usagePlanSource = value;
    await _save();
  }

  Future<void> setTaskView(String value) async {
    await load();
    if (!['project', 'timeline'].contains(value)) return;
    _taskView = value;
    await _save();
  }

  Future<void> setTaskSort(String value) async {
    await load();
    if (!['created', 'updated'].contains(value)) return;
    _taskSort = value;
    await _save();
  }

  Future<void> _save() {
    final value = jsonEncode({
      'theme': _theme.name,
      'language': _language,
      'textScale': _textScale,
      'uiFontSizePx': _uiFontSizePx,
      'codeFontSize': _codeFontSize,
      'taskView': _taskView,
      'taskSort': _taskSort,
        'lightCodeTheme': _lightCodeTheme,
        'darkCodeTheme': _darkCodeTheme,
        'showLineNumbers': _showLineNumbers,
        'wrapLongLines': _wrapLongLines,
        if (_usagePlanSource != null) 'usagePlanSource': _usagePlanSource
      });
    notifyListeners();
    final write = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, value);
    });
    _writes = write.catchError((_) {});
    return write;
  }
}

class ClientPreferencesScope extends InheritedNotifier<ClientPreferences> {
  const ClientPreferencesScope(
      {super.key, required ClientPreferences preferences, required super.child})
      : super(notifier: preferences);
  static ClientPreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ClientPreferencesScope>()
      ?.notifier;
}

String uiText(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'zh' ? chinese : english;

/// Preserve the platform's nonlinear accessibility scaling and apply the
/// client preference once, outside every page and popup.
class ClientTextScaler extends TextScaler {
  const ClientTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;

  static TextScaler systemScaler(TextScaler scaler) =>
      scaler is ClientTextScaler ? scaler.system : scaler;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is ClientTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
