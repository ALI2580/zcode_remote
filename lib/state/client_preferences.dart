import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientPreferences extends ChangeNotifier {
  static const storageKey = 'zcode_remote_client_preferences_v1';
  ThemeMode _theme = ThemeMode.system;
  String _language = 'system';
  double _textScale = 1;
  double _codeFontSize = 13;
  String _taskView = 'project';
  String _taskSort = 'updated';
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  ThemeMode get theme => _theme;
  String get language => _language;
  double get textScale => _textScale;
  double get codeFontSize => _codeFontSize;
  String get taskView => _taskView;
  String get taskSort => _taskSort;
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
        _textScale = _bounded(raw['textScale'], .8, 1.4, 1);
        _codeFontSize = _bounded(raw['codeFontSize'], 10, 20, 13);
        _taskView = raw['taskView'] == 'timeline' ? 'timeline' : 'project';
        _taskSort = raw['taskSort'] == 'created' ? 'created' : 'updated';
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

  Future<void> setTextScale(double value) async {
    await load();
    _textScale = _bounded(value, .8, 1.4, 1);
    await _save();
  }

  Future<void> setCodeFontSize(double value) async {
    await load();
    _codeFontSize = _bounded(value, 10, 20, 13);
    await _save();
  }

  Future<void> resetAppearance() async {
    await load();
    _theme = ThemeMode.system;
    _textScale = 1;
    _codeFontSize = 13;
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
      'codeFontSize': _codeFontSize,
      'taskView': _taskView,
      'taskSort': _taskSort
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
