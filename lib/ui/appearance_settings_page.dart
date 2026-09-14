import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/client_preferences.dart';
import 'code_renderer.dart';
import 'theme.dart';

/// Standalone U16 appearance surface. SettingsCenterPage can embed this page
/// after its section shell is released by the Settings workstream.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({
    super.key,
    required this.preferences,
    this.embedded = false,
  });

  final ClientPreferences preferences;
  final bool embedded;

  static const _previewSource =
      'class WorkspacePreview {\n  final codeFontSize = 18;\n  return true;\n}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final body = LayoutBuilder(
          builder: (context, constraints) {
            final children = _children(context);
            if (embedded) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );
            }
            return ListView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 500 ? 16 : 28,
                vertical: 20,
              ),
              children: children,
            );
          },
        );
        if (embedded) return body;
        return Scaffold(
          appBar: AppBar(
            title: Text(uiText(context, '外观', 'Appearance')),
          ),
          body: body,
        );
      },
    );
  }

  List<Widget> _children(BuildContext context) {
    final prefs = preferences;
    final compact = MediaQuery.sizeOf(context).width < 500;
    final divider = Divider(
      height: 1,
      color: ZInk.of(Theme.of(context).colorScheme).border,
    );
    return [
      _heading(
        context,
        title: uiText(context, '界面设置', 'Interface'),
        description: uiText(
          context,
          '设置应用主题和界面文字大小。',
          'App theme and interface text size.',
        ),
      ),
      _groupCard(
        context,
        children: [
          _themeModeRow(context, compact),
          divider,
          _fontSizeRow(
            context,
            key: const ValueKey('appearance-ui-font-size'),
            title: uiText(context, '界面字号', 'Interface text size'),
            description: uiText(
              context,
              '调整应用界面的文字大小，图标和布局尺寸不受影响。',
              'Adjust interface text size; icons and layout are unaffected.',
            ),
            value: prefs.uiFontSizePx,
            onChanged: (value) => unawaited(prefs.setUiFontSizePx(value)),
            compact: compact,
          ),
        ],
      ),
      const SizedBox(height: 24),
      _heading(
        context,
        title: uiText(context, '代码设置', 'Code'),
        description: uiText(
          context,
          '设置代码内容的主题、字号和显示方式。',
          'Code theme, font size and display.',
        ),
      ),
      _groupCard(
        context,
        children: [
          _themeSelector(
            context,
            key: const ValueKey('appearance-light-code-theme'),
            title: uiText(context, '浅色代码主题', 'Light code theme'),
            description: uiText(
              context,
              '浅色界面下代码内容使用的高亮主题。',
              'Highlight theme for code in the light interface.',
            ),
            value: prefs.lightCodeThemeId,
            onChanged: (value) {
              if (value != null) unawaited(prefs.setLightCodeTheme(value));
            },
            compact: compact,
          ),
          divider,
          _themeSelector(
            context,
            key: const ValueKey('appearance-dark-code-theme'),
            title: uiText(context, '深色代码主题', 'Dark code theme'),
            description: uiText(
              context,
              '深色界面下代码内容使用的高亮主题。',
              'Highlight theme for code in the dark interface.',
            ),
            value: prefs.darkCodeThemeId,
            onChanged: (value) {
              if (value != null) unawaited(prefs.setDarkCodeTheme(value));
            },
            compact: compact,
          ),
          divider,
          _switchRow(
            context,
            key: const ValueKey('appearance-show-line-numbers'),
            title: uiText(context, '显示行号', 'Show line numbers'),
            description: uiText(
              context,
              '在代码内容和差异视图中显示行号。',
              'Display line numbers in code and diff views.',
            ),
            value: prefs.showLineNumbers,
            onChanged: (value) => unawaited(prefs.setShowLineNumbers(value)),
          ),
          divider,
          _switchRow(
            context,
            key: const ValueKey('appearance-wrap-long-lines'),
            title: uiText(context, '长行自动换行', 'Wrap long lines'),
            description: uiText(
              context,
              '代码内容过长时自动换行。',
              'Wrap long code lines automatically.',
            ),
            value: prefs.wrapLongLines,
            onChanged: (value) => unawaited(prefs.setWrapLongLines(value)),
          ),
          divider,
          _fontSizeRow(
            context,
            key: const ValueKey('appearance-code-font-size'),
            title: uiText(context, '代码字号', 'Code font size'),
            description: uiText(
              context,
              '调整代码块、文件预览和差异视图的默认字号。',
              'Adjust default size for code blocks, files, and diffs.',
            ),
            value: prefs.codeFontSize.round(),
            onChanged: (value) => unawaited(prefs.setCodeFontSize(value)),
            compact: compact,
          ),
          const SizedBox(height: 16),
          _previewSection(context),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('appearance-reset'),
          onPressed: () => unawaited(prefs.resetAppearance()),
          child: Text(uiText(context, '恢复默认', 'Reset to defaults')),
        ),
      ),
    ];
  }

  Widget _heading(
    BuildContext context, {
    required String title,
    required String description,
  }) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: ink.subtlest)),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, {required List<Widget> children}) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.transparent,
          child: Column(children: children),
        ),
      ),
    );
  }

  Widget _themeModeRow(BuildContext context, bool compact) {
    final prefs = preferences;
    final control = DropdownButton<ThemeMode>(
      key: const ValueKey('appearance-theme-mode'),
      value: prefs.theme,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
          value: ThemeMode.system,
          child: Text(uiText(context, '跟随系统', 'System')),
        ),
        DropdownMenuItem(
          value: ThemeMode.light,
          child: Text(uiText(context, '浅色', 'Light')),
        ),
        DropdownMenuItem(
          value: ThemeMode.dark,
          child: Text(uiText(context, '深色', 'Dark')),
        ),
      ],
      onChanged: (value) {
        if (value != null) unawaited(prefs.setTheme(value));
      },
    );
    return _rowControl(
      context,
      title: uiText(context, '界面主题', 'Theme'),
      description: uiText(context, '选择浅色、深色或跟随系统主题。',
          'Choose light, dark, or follow the system theme.'),
      control: control,
      compact: compact,
    );
  }

  Widget _fontSizeRow(
    BuildContext context, {
    required Key key,
    required String title,
    required String description,
    required int value,
    required ValueChanged<int> onChanged,
    required bool compact,
  }) {
    final control = _FontSizeInput(
      key: key,
      value: value,
      onChanged: onChanged,
    );
    return _rowControl(
      context,
      title: title,
      description: description,
      control: control,
      compact: compact,
      controlWidth: 112,
      boxControl: false,
    );
  }

  Widget _rowControl(
    BuildContext context, {
    required String title,
    required String description,
    required Widget control,
    required bool compact,
    double controlWidth = 192,
    bool boxControl = true,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 2),
              Text(description,
                  style: TextStyle(
                      fontSize: 12,
                      color: ZInk.of(Theme.of(context).colorScheme).subtlest)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: compact ? double.infinity : controlWidth,
          child: boxControl ? _boxedControl(context, control) : control,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            ZInk.of(Theme.of(context).colorScheme).subtlest)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: boxControl ? _boxedControl(context, control) : control,
                ),
              ],
            )
          : row,
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required Key key,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        key: key,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            ZInk.of(Theme.of(context).colorScheme).subtlest)),
              ],
            ),
          ),
          _CompactSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _themeSelector(
    BuildContext context, {
    required Key key,
    required String title,
    required String description,
    required String value,
    required ValueChanged<String?> onChanged,
    required bool compact,
  }) {
    final control = DropdownButton<String>(
      key: key,
      value: CodeThemeCatalog.themeIds.contains(value) ? value : null,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: [
        for (final theme in CodeThemeCatalog.all)
          DropdownMenuItem<String>(
            value: theme.id,
            child: Text(theme.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
    return _rowControl(
      context,
      title: title,
      description: description,
      control: control,
      compact: compact,
    );
  }

  Widget _boxedControl(BuildContext context, Widget control) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: ink.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: control,
        ),
      ),
    );
  }

  Widget _previewSection(BuildContext context) {
    final prefs = preferences;
    final light =
        CodeThemeCatalog.byId(prefs.lightCodeThemeId, Brightness.light);
    final dark = CodeThemeCatalog.byId(prefs.darkCodeThemeId, Brightness.dark);
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(uiText(context, '代码预览', 'Code previews'),
            style: TextStyle(fontSize: 13, color: ink.subtlest)),
        const SizedBox(height: 8),
        _previewCard(context, light, uiText(context, '浅色代码', 'Light code')),
        const SizedBox(height: 12),
        _previewCard(context, dark, uiText(context, '深色代码', 'Dark code')),
      ],
    );
  }

  Widget _previewCard(
      BuildContext context, CodeThemeDefinition theme, String title) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.lineNumberForeground),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(title,
                style: TextStyle(color: theme.foreground, fontSize: 12)),
          ),
          CodeViewer(
            source: _previewSource,
            theme: theme,
            fontSize: preferences.codeFontSize,
            showLineNumbers: preferences.showLineNumbers,
            wrapLongLines: preferences.wrapLongLines,
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
    );
  }
}

class _FontSizeInput extends StatefulWidget {
  const _FontSizeInput(
      {super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_FontSizeInput> createState() => _FontSizeInputState();
}

class _FontSizeInputState extends State<_FontSizeInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late int _confirmed;

  @override
  void initState() {
    super.initState();
    _confirmed = _clamp(widget.value);
    _controller = TextEditingController(text: '$_confirmed');
    _focusNode = FocusNode()..addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant _FontSizeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _clamp(widget.value);
    if (next == _confirmed) return;
    _confirmed = next;
    _setText(next);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  int _clamp(int value) => value.clamp(12, 20);

  void _setText(int value) {
    final text = '$value';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _restore() => _setText(_confirmed);

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 12 || parsed > 20) {
      _restore();
      return;
    }
    final next = _clamp(parsed);
    final changed = next != _confirmed;
    _confirmed = next;
    _setText(next);
    if (changed) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _restore();
          node.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: 112,
        height: 28,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.right,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            suffixText: 'px',
            suffixStyle: TextStyle(fontSize: 12, color: ink.subtlest),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: ink.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: ink.border),
            ),
          ),
          onSubmitted: (_) {
            _commit();
            _focusNode.unfocus();
          },
          onTapOutside: (_) => _focusNode.unfocus(),
        ),
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onChanged == null ? null : () => onChanged!(!value),
            ),
          ),
          Transform.scale(
            scale: .62,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
