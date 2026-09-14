import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/model_connectivity.dart';
import '../state/model_provider_catalog.dart';
import 'model_connectivity_button.dart';

typedef ModelProviderEditorSaved = FutureOr<void> Function(
    ModelProviderEntry provider);

/// A self-contained provider editor for the official k8/cVt provider shape.
/// Provider fields commit on their official blur/Enter paths; model edits stay
/// local until the explicit Save action succeeds.
class ModelProviderEditor extends StatefulWidget {
  const ModelProviderEditor({
    super.key,
    required this.provider,
    required this.catalog,
    required this.connectivity,
    this.onSaved,
    this.onCancel,
    this.onComposerRefresh,
    this.useChinese = false,
    this.readOnlyEndpoints = false,
    this.readOnlyApiKey = false,
    this.hideConnectionSection = false,
    this.hideApiKeySection = false,
    this.nameEditable = true,
    this.modelsReadOnly = false,
    this.modelsEditMode,
    this.commitProviderFields = true,
    this.cleanupOnDispose = false,
  });

  final ModelProviderEntry provider;
  final ModelProvidersCatalog catalog;
  final ModelConnectivityController connectivity;
  final ModelProviderEditorSaved? onSaved;
  final VoidCallback? onCancel;
  final VoidCallback? onComposerRefresh;
  final bool useChinese;
  final bool readOnlyEndpoints;
  final bool readOnlyApiKey;

  /// Official coding-plan provider cards omit these sections entirely after
  /// entitlement resolution. Keep the distinction from read-only fields so a
  /// caller can reproduce the same layout without guessing from a name.
  final bool hideConnectionSection;
  final bool hideApiKeySection;
  final bool nameEditable;
  final bool modelsReadOnly;
  final String? modelsEditMode;
  final bool commitProviderFields;

  /// Enables the official provider-section cleanup when the parent switches
  /// provider or removes the editor. ModelEntryEditor does not use this path.
  final bool cleanupOnDispose;

  @override
  State<ModelProviderEditor> createState() => _ModelProviderEditorState();
}

class _EditableModel {
  _EditableModel(ModelEntry model)
      : raw = Map<String, dynamic>.from(model.raw),
        id = TextEditingController(text: model.id),
        name = TextEditingController(text: model.name),
        kinds = TextEditingController(text: model.kinds.join(', ')),
        contextWindow = TextEditingController(
            text: (model.contextWindow ?? _defaultContextWindow).toString()),
        maxOutputTokens = TextEditingController(
            text:
                (model.maxOutputTokens ?? _defaultMaxOutputTokens).toString()),
        inputModalities = TextEditingController(
            text: model.inputModalities.isEmpty
                ? 'text'
                : model.inputModalities.join(', '));

  _EditableModel.empty(String defaultKind)
      : raw = const {},
        id = TextEditingController(),
        name = TextEditingController(),
        kinds = TextEditingController(text: defaultKind),
        contextWindow = TextEditingController(),
        maxOutputTokens =
            TextEditingController(text: _defaultMaxOutputTokens.toString()),
        inputModalities = TextEditingController(text: 'text');

  final Map<String, dynamic> raw;
  final TextEditingController id;
  final TextEditingController name;
  final TextEditingController kinds;
  final TextEditingController contextWindow;
  final TextEditingController maxOutputTokens;
  final TextEditingController inputModalities;
  bool nameChanged = false;
  bool inputModalitiesChanged = false;

  void dispose() {
    id.dispose();
    name.dispose();
    kinds.dispose();
    contextWindow.dispose();
    maxOutputTokens.dispose();
    inputModalities.dispose();
  }
}

// Frozen src-DHgFesxz.js: ff=200e3, df=128e3; D8 uses these when a model
// omits contextWindow or maxOutputTokens.
const int _defaultContextWindow = 200000;
const int _defaultMaxOutputTokens = 128000;

class _ModelProviderEditorState extends State<ModelProviderEditor> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final FocusNode _nameFocus;
  late final FocusNode _baseUrlFocus;
  late final FocusNode _apiKeyFocus;
  late final bool _hadApiFormat;
  late final bool _hadApiKey;
  late String _apiFormat;
  late String _initialApiFormat;
  bool _apiFormatChanged = false;
  int _formatRevision = 0;
  late String _confirmedName;
  late String _confirmedBaseUrl;
  late String _confirmedApiKey;
  bool _nameComposing = false;
  Future<void> _providerCommitTail = Future<void>.value();
  late Map<String, dynamic> _confirmedProviderRaw;
  late List<_EditableModel> _models;
  bool _saving = false;
  bool _cancelling = false;
  bool _cancelled = false;
  bool _internalCommit = false;
  String? _error;

  String _text(String chinese, String english) =>
      widget.useChinese ? chinese : english;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.name);
    final endpoints = widget.provider.raw['endpoints'];
    final baseUrl = endpoints is Map && endpoints['baseURL'] is String
        ? endpoints['baseURL'] as String
        : '';
    _baseUrl = TextEditingController(text: baseUrl);
    _initialApiFormat = widget.provider.apiFormat;
    _apiFormat = widget.provider.apiFormat;
    _hadApiFormat = widget.provider.raw.containsKey('apiFormat');
    _hadApiKey = widget.provider.raw.containsKey('apiKey');
    _apiKey = TextEditingController(
        text: widget.provider.raw['apiKey'] is String
            ? widget.provider.raw['apiKey'] as String
            : '');
    _confirmedName = _name.text;
    _confirmedBaseUrl = _baseUrl.text;
    _confirmedApiKey = _apiKey.text;
    _confirmedProviderRaw = _cloneMap(widget.provider.raw);
    _nameFocus = FocusNode();
    _baseUrlFocus = FocusNode();
    _apiKeyFocus = FocusNode();
    _models = [
      for (final model in widget.provider.models) _EditableModel(model),
    ];
    for (final controller in [_name, _baseUrl, _apiKey]) {
      controller.addListener(_onDraftChanged);
    }
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _scheduleProviderCommit('name');
    });
    _baseUrlFocus.addListener(() {
      if (!_baseUrlFocus.hasFocus) _scheduleProviderCommit('baseURL');
    });
    _apiKeyFocus.addListener(() {
      if (!_apiKeyFocus.hasFocus) _scheduleProviderCommit('apiKey');
    });
  }

  @override
  void dispose() {
    if (widget.cleanupOnDispose && !_cancelled && !_internalCommit) {
      // Snapshot before disposing controllers. The write waits behind any
      // blur commit, matching the provider switch cleanup ordering.
      final cleanupProvider = _effectiveProvider;
      final cleanupDraft = _cloneMap(_providerFieldDraft());
      final cleanupFormatRevision = _formatRevision;
      unawaited(_providerCommitTail.then<void>((_) => _commitCleanupSnapshot(
          cleanupProvider, cleanupDraft, cleanupFormatRevision)));
    }
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _nameFocus.dispose();
    _baseUrlFocus.dispose();
    _apiKeyFocus.dispose();
    for (final model in _models) {
      model.dispose();
    }
    super.dispose();
  }

  Future<void> _commitCleanupSnapshot(
    ModelProviderEntry provider,
    Map<String, dynamic> draft,
    int formatRevision,
  ) async {
    final saved = await widget.catalog.saveProviderDraft(
      provider,
      draft,
      clearHeaders: provider.raw.containsKey('headers'),
    );
    // Route cleanup is allowed to finish after the editor is unmounted. The
    // scoped Composer refresh belongs to the captured parent source and must
    // still run after a successful authoritative save.
    if (!saved) return;
    widget.onComposerRefresh?.call();
    if (!mounted) return;
    final updated = widget.catalog.items
        .where((item) => item.id == widget.provider.id)
        .firstOrNull;
    if (updated == null) return;
    _confirmedProviderRaw = _cloneMap(updated.raw);
    _confirmedName = updated.name;
    _confirmedBaseUrl = updated.baseURL ?? '';
    _confirmedApiKey =
        updated.raw['apiKey'] is String ? updated.raw['apiKey'] as String : '';
    if (_formatRevision == formatRevision) {
      _apiFormat = updated.apiFormat;
      _initialApiFormat = updated.apiFormat;
      _apiFormatChanged = false;
    }
  }

  void _onDraftChanged() {
    // Controller edits invalidate the current connectivity draft. Format
    // changes increment their own revision in the dropdown handler below so
    // a slower name/key read-back cannot overwrite that newer choice.
    widget.connectivity.invalidateProvider(widget.provider.id);
    if (mounted) setState(() => _error = null);
  }

  ModelProviderEntry get _effectiveProvider =>
      ModelProviderEntry.fromRaw(_confirmedProviderRaw);

  String get _modelEditMode =>
      widget.modelsEditMode ?? (widget.modelsReadOnly ? 'read-only' : 'full');

  bool get _modelsAreReadOnly => _modelEditMode == 'read-only';

  bool get _contextWindowOnly => _modelEditMode == 'context-window-only';

  bool get _providerNameReadOnly => !widget.nameEditable;

  bool get _formatReadOnly => widget.readOnlyEndpoints;

  Map<String, dynamic> _providerFieldDraft() {
    final endpoints = _cloneMap(_effectiveProvider.raw['endpoints']);
    if (!widget.readOnlyEndpoints) {
      endpoints['baseURL'] = _baseUrl.text.trim();
      if (_apiFormatChanged) {
        final path = _pathForFormat(_apiFormat);
        if (path != null) endpoints['paths'] = {_apiFormat: path};
      }
    }
    final draft = <String, dynamic>{
      // S8 falls back to the confirmed provider name when the editor value
      // is empty; the provider schema itself requires a non-empty name.
      'name': _name.text.trim().isEmpty
          ? _effectiveProvider.name
          : _name.text.trim(),
      'endpoints': endpoints,
    };
    if (_hadApiFormat || _apiFormat.trim().isNotEmpty) {
      draft['apiFormat'] = _apiFormat.trim();
    }
    if (_apiFormatChanged) {
      draft['defaultKind'] = _defaultKindForFormat(_apiFormat);
    }
    if (_hadApiKey || _apiKey.text.isNotEmpty || _confirmedApiKey.isNotEmpty) {
      draft['apiKey'] = _apiKey.text;
    }
    return draft;
  }

  Future<void> _commitProviderField(String field,
      {bool allowUnmount = false}) async {
    if (!widget.commitProviderFields || (!mounted && !allowUnmount)) {
      return;
    }
    if (field == 'name' && !widget.nameEditable) return;
    if (field == 'baseURL' && widget.readOnlyEndpoints) return;
    if (field == 'apiKey' && widget.readOnlyApiKey) return;
    if (field == 'apiFormat' && widget.readOnlyEndpoints) return;
    final value = switch (field) {
      'name' => _name.text,
      'baseURL' => _baseUrl.text,
      'apiKey' => _apiKey.text,
      'apiFormat' => _apiFormat,
      _ => '',
    };
    final previous = switch (field) {
      'name' => _confirmedName,
      'baseURL' => _confirmedBaseUrl,
      'apiKey' => _confirmedApiKey,
      'apiFormat' => _effectiveProvider.apiFormat,
      _ => value,
    };
    final cleanup = field == 'cleanup';
    final hasProviderDraft = _name.text != _confirmedName ||
        _baseUrl.text != _confirmedBaseUrl ||
        _apiKey.text != _confirmedApiKey ||
        _apiFormatChanged ||
        _confirmedProviderRaw.containsKey('headers');
    if (!cleanup &&
        value == previous &&
        !(field == 'baseURL' && _apiFormatChanged) &&
        !(field == 'apiKey' && _confirmedProviderRaw.containsKey('headers')) &&
        !(field == 'apiFormat' && _apiFormatChanged)) {
      return;
    }
    if (cleanup && !hasProviderDraft) {
      return;
    }
    final submittedDraft = _cloneMap(_providerFieldDraft());
    final submittedProvider = _effectiveProvider;
    final submittedFormatRevision = _formatRevision;
    final saved = await widget.catalog.saveProviderDraft(
      submittedProvider,
      submittedDraft,
      clearHeaders: submittedProvider.raw.containsKey('headers'),
    );
    if (!saved) {
      if (!mounted) return;
      final error = widget.catalog.saveError(widget.provider.id);
      setState(() => _error =
          error == null ? _text('保存失败，请重试。', 'Save failed. Retry.') : '$error');
      return;
    }
    // A blur/cleanup commit can finish after route disposal. Keep the
    // confirmed remote write useful to existing Composer controllers even
    // when this editor can no longer update its local widgets.
    if (!mounted) {
      widget.onComposerRefresh?.call();
      return;
    }
    final updated = widget.catalog.items
        .where((item) => item.id == widget.provider.id)
        .firstOrNull;
    if (updated == null) return;
    _confirmedProviderRaw = _cloneMap(updated.raw);
    _confirmedName = updated.name;
    _confirmedBaseUrl = updated.baseURL ?? '';
    _confirmedApiKey =
        updated.raw['apiKey'] is String ? updated.raw['apiKey'] as String : '';
    if (_formatRevision == submittedFormatRevision) {
      _apiFormat = updated.apiFormat;
      _initialApiFormat = updated.apiFormat;
      _apiFormatChanged = false;
    }
    // A later edit may be visible while this request is in flight. Only the
    // authoritative read-back becomes confirmed state; the live controllers
    // remain untouched for the queued next commit.
    widget.onComposerRefresh?.call();
  }

  void _scheduleProviderCommit(String field) {
    if (!widget.commitProviderFields || !mounted) return;
    _providerCommitTail = _providerCommitTail
        .then<void>((_) => _commitProviderField(field))
        .catchError((_) {});
  }

  /// Flushes provider fields on the official section cleanup path. Model
  /// edits remain in [_models] and are intentionally excluded; they only
  /// reach the service from the explicit Save action.
  Future<void> _flushProviderFields({bool allowUnmount = false}) async {
    if (!widget.commitProviderFields || (!mounted && !allowUnmount)) return;
    // S8 computes one cVt payload from the latest draft during cleanup. A
    // single queued commit avoids four writes (and lets the read-back clear
    // headers before cleanup runs again after focus loss).
    if (allowUnmount && !mounted) {
      _providerCommitTail = _providerCommitTail
          .then<void>(
              (_) => _commitProviderField('cleanup', allowUnmount: true))
          .catchError((_) {});
    } else {
      _scheduleProviderCommit('cleanup');
    }
    await _providerCommitTail;
  }

  Future<void> _cancel() async {
    if (_saving || _cancelling) return;
    setState(() {
      _cancelling = true;
      _cancelled = true;
      // A cleanup failure must remain visible so the provider draft can be
      // retried instead of being silently discarded on route exit.
      _error = null;
    });
    await _flushProviderFields();
    if (!mounted) return;
    if (_error != null) {
      setState(() {
        _cancelling = false;
        _cancelled = false;
      });
      return;
    }
    widget.onCancel?.call();
  }

  void _rollbackField(String field) {
    switch (field) {
      case 'name':
        _name.value = TextEditingValue(text: _confirmedName);
      case 'baseURL':
        _baseUrl.value = TextEditingValue(text: _confirmedBaseUrl);
      case 'apiKey':
        _apiKey.value = TextEditingValue(text: _confirmedApiKey);
    }
    _onDraftChanged();
  }

  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event, String field) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final composing = field == 'name' &&
        (_nameComposing ||
            (_name.value.composing.isValid &&
                !_name.value.composing.isCollapsed));
    if (composing &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.enter)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _rollbackField(field);
      node.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _scheduleProviderCommit(field);
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onModelChanged() {
    widget.connectivity.invalidateProvider(widget.provider.id);
    if (mounted) setState(() => _error = null);
  }

  Map<String, dynamic>? _draft({bool showError = false}) {
    final endpoints = _cloneMap(_effectiveProvider.raw['endpoints']);
    if (!widget.readOnlyEndpoints) {
      endpoints['baseURL'] = _baseUrl.text.trim();
      if (_apiFormatChanged) {
        final path = _pathForFormat(_apiFormat);
        if (path != null) endpoints['paths'] = {_apiFormat: path};
      }
    }
    final models = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final model in _models) {
      final id = model.id.text.trim();
      final name = model.name.text.trim();
      final kinds = _tokens(model.kinds.text, allowed: _allowedKinds);
      final context = int.tryParse(model.contextWindow.text.trim());
      final maxOutputTokens = int.tryParse(model.maxOutputTokens.text.trim());
      final inputModalities =
          _tokens(model.inputModalities.text, allowed: _allowedInputModalities);
      if (id.isEmpty || kinds.isEmpty || context == null || context <= 0) {
        if (showError) {
          setState(() => _error = _text('每个模型都需要有效的 ID、API 格式和上下文窗口。',
              'Every model needs a valid ID, API kinds, and context window.'));
        }
        return null;
      }
      if (maxOutputTokens == null || maxOutputTokens <= 0) {
        if (showError) {
          setState(() => _error = _text('最大输出 Token 必须是正整数。',
              'Maximum output tokens must be a positive integer.'));
        }
        return null;
      }
      if (!inputModalities.contains('text')) {
        if (showError) {
          setState(() => _error =
              _text('输入类型必须包含文本。', 'Input modalities must include text.'));
        }
        return null;
      }
      if (!ids.add(id)) {
        if (showError) {
          setState(
              () => _error = _text('模型 ID 必须唯一。', 'Model IDs must be unique.'));
        }
        return null;
      }
      models.add(_modelRaw(
        model,
        id: id,
        name: name,
        kinds: kinds,
        contextWindow: context,
        maxOutputTokens: maxOutputTokens,
        inputModalities: inputModalities,
      ));
    }
    final providerName =
        _name.text.trim().isEmpty ? _effectiveProvider.name : _name.text.trim();
    if (providerName.isEmpty || _baseUrl.text.trim().isEmpty) {
      if (showError) {
        setState(() => _error = _text(
            '供应商名称和 Base URL 必填。', 'Provider name and Base URL are required.'));
      }
      return null;
    }
    final draft = <String, dynamic>{
      'name': providerName,
      'endpoints': endpoints,
      'models': models,
    };
    if (_hadApiFormat || _apiFormat.trim().isNotEmpty) {
      draft['apiFormat'] = _apiFormat.trim();
    }
    if (_apiFormatChanged) {
      draft['defaultKind'] = _defaultKindForFormat(_apiFormat);
    }
    if (_hadApiKey || _apiKey.text.isNotEmpty) {
      draft['apiKey'] = _apiKey.text;
    }
    return draft;
  }

  static const _knownFormats = [
    'anthropic-messages',
    'openai-chat-completions',
    'openai-responses',
  ];

  static const _allowedKinds = ['anthropic', 'openai-compatible', 'openai'];
  static const _allowedInputModalities = ['text', 'image', 'video', 'pdf'];

  List<String> _tokens(String value, {List<String>? allowed}) {
    final values = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
    final result = <String>[];
    for (final item in values) {
      if (allowed != null && !allowed.contains(item)) continue;
      if (!result.contains(item)) result.add(item);
    }
    return result;
  }

  List<String> _unknownTokens(
    _EditableModel model,
    String key, {
    required List<String> known,
  }) {
    final value = model.raw[key];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String &&
            item.trim().isNotEmpty &&
            !known.contains(item.trim().toLowerCase()))
          item.trim(),
    ];
  }

  List<String> _unknownInputModalities(_EditableModel model) {
    final modalities = model.raw['modalities'];
    final value =
        modalities is Map ? modalities['input'] : model.raw['inputModalities'];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String &&
            item.trim().isNotEmpty &&
            !_allowedInputModalities.contains(item.trim().toLowerCase()))
          item.trim(),
    ];
  }

  void _setModelTokens(
      TextEditingController controller, Iterable<String> values) {
    controller.text = values.join(', ');
    _onModelChanged();
  }

  Widget _modelTokenChoices(
    _EditableModel model, {
    required TextEditingController controller,
    required List<String> choices,
    required String label,
    required bool readOnly,
    required bool lockFirst,
    bool markModalitiesChanged = false,
  }) {
    final selected = _tokens(controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final choice in choices)
              FilterChip(
                label: Text(choice),
                selected: selected.contains(choice),
                onSelected: readOnly || (lockFirst && choice == choices.first)
                    ? null
                    : (value) {
                        final next = {...selected};
                        if (value) {
                          next.add(choice);
                        } else {
                          next.remove(choice);
                        }
                        if (lockFirst) next.add(choices.first);
                        _setModelTokens(controller, next);
                        if (markModalitiesChanged) {
                          model.inputModalitiesChanged = true;
                        }
                      },
              ),
          ],
        ),
      ],
    );
  }

  String _defaultKindForFormat(String format) =>
      format == 'anthropic-messages' ? 'anthropic' : 'openai-compatible';

  String? _pathForFormat(String format) => switch (format) {
        'anthropic-messages' => '/v1/messages',
        'openai-chat-completions' => '/chat/completions',
        'openai-responses' => '/responses',
        _ => null,
      };

  ModelEntry _modelEntry(_EditableModel editable) =>
      ModelEntry.fromRaw(_modelRaw(
        editable,
        id: editable.id.text.trim(),
        name: editable.name.text.trim(),
        kinds: _tokens(editable.kinds.text, allowed: _allowedKinds),
        contextWindow: int.tryParse(editable.contextWindow.text.trim()) ?? 0,
        maxOutputTokens:
            int.tryParse(editable.maxOutputTokens.text.trim()) ?? 0,
        inputModalities: _tokens(editable.inputModalities.text,
            allowed: _allowedInputModalities),
      ));

  Map<String, dynamic> _modelRaw(
    _EditableModel editable, {
    required String id,
    required String name,
    required List<String> kinds,
    required int contextWindow,
    required int maxOutputTokens,
    required List<String> inputModalities,
  }) {
    if (_contextWindowOnly) {
      return {
        ...editable.raw,
        'contextWindow': contextWindow,
      };
    }
    final raw = <String, dynamic>{
      ...editable.raw,
      'id': id,
      'contextWindow': contextWindow,
      'kinds': [
        ...kinds,
        ..._unknownTokens(editable, 'kinds', known: _allowedKinds),
      ],
      if (kinds.isNotEmpty)
        'defaultKind': kinds.contains(_defaultKindForFormat(_apiFormat))
            ? _defaultKindForFormat(_apiFormat)
            : kinds.contains(_effectiveProvider.defaultKind)
                ? _effectiveProvider.defaultKind
                : kinds.first,
    };
    raw['maxOutputTokens'] = maxOutputTokens;
    raw['modalities'] = {
      'input': [
        ...inputModalities,
        ..._unknownInputModalities(editable),
      ],
      'output': ['text'],
    };
    if (name.trim().isEmpty ||
        (!editable.nameChanged && !editable.raw.containsKey('name'))) {
      raw.remove('name');
    } else {
      raw['name'] = name.trim();
    }
    if (editable.inputModalitiesChanged) raw['modalitiesConfigured'] = true;
    // reasoning/priority and any provider-specific metadata remain untouched
    // in editable.raw; only the D8/xVt fields above are committed from input.
    return raw;
  }

  Future<void> _testModel(_EditableModel editable) async {
    final draft = _draft(showError: true);
    if (draft == null) return;
    final model = _modelEntry(editable);
    await widget.connectivity.testModelConnectivity(
      provider: _effectiveProvider,
      model: model,
      draft: draft,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _internalCommit = true;
      _error = null;
    });
    // A focus transition can enqueue the official blur commit immediately
    // before this button handler. Let it finish first so the whole-provider
    // Save cannot lose that field to catalog's per-provider write gate.
    await _providerCommitTail;
    if (!mounted) return;
    final draft = _draft(showError: true);
    if (draft == null) {
      setState(() {
        _saving = false;
        _internalCommit = false;
      });
      return;
    }
    final submittedFormatRevision = _formatRevision;
    final saved = await widget.catalog.saveProviderDraft(
      _effectiveProvider,
      draft,
      clearHeaders: _effectiveProvider.raw.containsKey('headers'),
    );
    if (!mounted) return;
    if (!saved) {
      final error = widget.catalog.saveError(widget.provider.id);
      setState(() {
        _saving = false;
        _internalCommit = false;
        _error = error == null
            ? _text('保存失败，请重试。', 'Save failed. Retry.')
            : '$error';
      });
      return;
    }
    final updated = widget.catalog.items
        .where((item) => item.id == widget.provider.id)
        .firstOrNull;
    setState(() => _saving = false);
    if (updated != null) {
      _confirmedProviderRaw = _cloneMap(updated.raw);
      _confirmedName = updated.name;
      _confirmedBaseUrl = updated.baseURL ?? '';
      _confirmedApiKey = updated.raw['apiKey'] is String
          ? updated.raw['apiKey'] as String
          : '';
      if (_formatRevision == submittedFormatRevision) {
        _apiFormat = updated.apiFormat;
        _initialApiFormat = updated.apiFormat;
        _apiFormatChanged = false;
      }
    }
    await widget.onSaved?.call(updated ?? _effectiveProvider);
    widget.onComposerRefresh?.call();
  }

  void _addModel() {
    if (_modelsAreReadOnly || _contextWindowOnly) return;
    final defaultKind = _defaultKindForFormat(_apiFormat);
    setState(() => _models.add(_EditableModel.empty(defaultKind)));
    _onModelChanged();
  }

  void _removeModel(int index) {
    if (_modelsAreReadOnly || _contextWindowOnly) return;
    final model = _models.removeAt(index);
    model.dispose();
    setState(() {});
    _onModelChanged();
  }

  Widget _modelForm(_EditableModel model, int index) {
    final current = _modelEntry(model);
    final attempt =
        widget.connectivity.attemptFor(widget.provider.id, current.id.trim());
    final dynamicHeaders = widget.connectivity.dynamicHeadersResolver != null &&
        isZcodePlanProvider(_effectiveProvider, _effectiveProvider.raw);
    return Card(
      key: ValueKey('model-editor-$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: model.id,
                    readOnly: _modelsAreReadOnly || _contextWindowOnly,
                    decoration:
                        InputDecoration(labelText: _text('模型 ID', 'Model ID')),
                    onChanged: (_) => _onModelChanged(),
                  ),
                ),
                IconButton(
                  tooltip: _text('删除模型', 'Delete model'),
                  onPressed: _saving || _modelsAreReadOnly || _contextWindowOnly
                      ? null
                      : () => _removeModel(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: model.name,
              readOnly: _modelsAreReadOnly || _contextWindowOnly,
              decoration:
                  InputDecoration(labelText: _text('模型名称', 'Model name')),
              onChanged: (_) {
                model.nameChanged = true;
                _onModelChanged();
              },
            ),
            const SizedBox(height: 8),
            _modelTokenChoices(
              model,
              controller: model.kinds,
              choices: _allowedKinds,
              label: _text('API 格式', 'API kinds'),
              readOnly: _modelsAreReadOnly || _contextWindowOnly,
              lockFirst: false,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: model.contextWindow,
              readOnly: _modelsAreReadOnly,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: _text('上下文窗口', 'Context window')),
              onChanged: (_) => _onModelChanged(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: model.maxOutputTokens,
              readOnly: _modelsAreReadOnly || _contextWindowOnly,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: _text('最大输出 Token', 'Max output tokens')),
              onChanged: (_) => _onModelChanged(),
            ),
            const SizedBox(height: 8),
            _modelTokenChoices(
              model,
              controller: model.inputModalities,
              choices: _allowedInputModalities,
              label: _text('输入类型', 'Input modalities'),
              readOnly: _modelsAreReadOnly || _contextWindowOnly,
              lockFirst: true,
              markModalitiesChanged: true,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _text('输出类型：text（固定）', 'Output modalities: text (fixed)'),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (!_modelsAreReadOnly && !widget.hideConnectionSection) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ModelConnectivityButton(
                  modelId: current.id,
                  hasApiKey: _apiKey.text.trim().isNotEmpty,
                  allowApiKeyless: dynamicHeaders,
                  pending: attempt?.pending == true,
                  outcome: attempt?.outcome,
                  useChinese: widget.useChinese,
                  onTest: () => _testModel(model),
                ),
              ),
              if (attempt?.outcome != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ModelConnectivityResultPill(
                      outcome: attempt!.outcome!,
                      useChinese: widget.useChinese,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.connectivity,
      builder: (context, _) => Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_text('编辑供应商', 'Edit provider'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Focus(
                onKeyEvent: (node, event) =>
                    _handleFieldKey(_nameFocus, event, 'name'),
                child: TextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  readOnly: _providerNameReadOnly,
                  decoration: InputDecoration(labelText: _text('名称', 'Name')),
                  onChanged: (_) {
                    _nameComposing = _name.value.composing.isValid &&
                        !_name.value.composing.isCollapsed;
                  },
                  onEditingComplete: () {
                    if (!_nameComposing) {
                      _scheduleProviderCommit('name');
                    }
                  },
                ),
              ),
              if (!widget.hideConnectionSection) ...[
                const SizedBox(height: 12),
                Focus(
                  onKeyEvent: (node, event) =>
                      _handleFieldKey(_baseUrlFocus, event, 'baseURL'),
                  child: TextField(
                    controller: _baseUrl,
                    focusNode: _baseUrlFocus,
                    readOnly: widget.readOnlyEndpoints,
                    decoration: InputDecoration(
                        labelText: _text('Base URL', 'Base URL')),
                    keyboardType: TextInputType.url,
                    onEditingComplete: () => _scheduleProviderCommit('baseURL'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _apiFormat.trim().isEmpty ? null : _apiFormat,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: _text('连接方式', 'API format')),
                  items: [
                    for (final format in [
                      ..._knownFormats,
                      if (!_knownFormats.contains(_apiFormat)) _apiFormat,
                    ])
                      DropdownMenuItem(value: format, child: Text(format)),
                  ],
                  onChanged: _formatReadOnly
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _apiFormat = value;
                            _apiFormatChanged = _apiFormat != _initialApiFormat;
                            _formatRevision++;
                          });
                          _onDraftChanged();
                          _scheduleProviderCommit('apiFormat');
                        },
                ),
              ],
              if (!widget.hideApiKeySection) ...[
                const SizedBox(height: 12),
                Focus(
                  onKeyEvent: (node, event) =>
                      _handleFieldKey(_apiKeyFocus, event, 'apiKey'),
                  child: TextField(
                    controller: _apiKey,
                    focusNode: _apiKeyFocus,
                    readOnly: widget.readOnlyApiKey,
                    decoration:
                        InputDecoration(labelText: _text('API 密钥', 'API key')),
                    obscureText: true,
                    onEditingComplete: () => _scheduleProviderCommit('apiKey'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(_text('模型', 'Models'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (var index = 0; index < _models.length; index++)
                _modelForm(_models[index], index),
              if (!_modelsAreReadOnly && !_contextWindowOnly)
                TextButton.icon(
                  onPressed: _saving ? null : _addModel,
                  icon: const Icon(Icons.add),
                  label: Text(_text('添加模型', 'Add model')),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving || _cancelling ? null : _cancel,
                    child: Text(_text('取消', 'Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_text('保存', 'Save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _cloneMap(dynamic value) => value is Map
    ? {
        for (final entry in value.entries)
          '${entry.key}': _cloneValue(entry.value),
      }
    : <String, dynamic>{};

dynamic _cloneValue(dynamic value) {
  if (value is Map) return _cloneMap(value);
  if (value is List) return [for (final item in value) _cloneValue(item)];
  return value;
}

typedef ModelEntryEditorCommit = FutureOr<bool> Function(
    Map<String, dynamic> model);

/// The model-row editor used by Settings. It deliberately receives one
/// provider and one model, so testing an edited row sends the visible draft
/// without saving unrelated provider fields first.
class ModelEntryEditor extends StatefulWidget {
  const ModelEntryEditor({
    super.key,
    required this.provider,
    required this.model,
    required this.connectivity,
    this.onCommit,
    this.onSaved,
    this.onCancel,
    this.useChinese = false,
    this.readOnly = false,
    this.editMode = 'full',
  });

  final ModelProviderEntry provider;
  final ModelEntry? model;
  final ModelConnectivityController connectivity;
  final ModelEntryEditorCommit? onCommit;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;
  final bool useChinese;
  final bool readOnly;
  final String editMode;

  @override
  State<ModelEntryEditor> createState() => _ModelEntryEditorState();
}

class _ModelEntryEditorState extends State<ModelEntryEditor> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _kinds;
  late final TextEditingController _contextWindow;
  late final TextEditingController _maxOutputTokens;
  late final TextEditingController _inputModalities;
  late final Map<String, dynamic> _raw;
  bool _modalitiesChanged = false;
  bool _saving = false;
  String? _error;

  static const _allowedKinds = ['anthropic', 'openai-compatible', 'openai'];
  static const _allowedInputModalities = ['text', 'image', 'video', 'pdf'];

  String _text(String chinese, String english) =>
      widget.useChinese ? chinese : english;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    _raw = model == null ? <String, dynamic>{} : _cloneMap(model.raw);
    final preferredKind = _preferredKind();
    final knownKinds = model == null
        ? const <String>[]
        : model.kinds.where(_allowedKinds.contains).toList();
    final kinds = knownKinds.isNotEmpty
        ? model!.kinds
        : <String>[preferredKind, ...?model?.kinds];
    final input = model?.inputModalities.isNotEmpty == true
        ? model!.inputModalities
        : const <String>['text'];
    _id = TextEditingController(text: model?.id ?? '');
    _name = TextEditingController(
        text: _raw['name'] is String ? _raw['name'] as String : '');
    _kinds = TextEditingController(text: kinds.join(', '));
    _contextWindow = TextEditingController(
        text: (model?.contextWindow ?? _defaultContextWindow).toString());
    _maxOutputTokens = TextEditingController(
        text: (model?.maxOutputTokens ?? _defaultMaxOutputTokens).toString());
    _inputModalities = TextEditingController(text: input.join(', '));
  }

  String _preferredKind() {
    if (_allowedKinds.contains(widget.provider.defaultKind)) {
      return widget.provider.defaultKind;
    }
    return switch (widget.provider.apiFormat) {
      'anthropic' || 'anthropic-messages' => 'anthropic',
      'openai' || 'openai-responses' => 'openai',
      _ => 'openai-compatible',
    };
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _kinds.dispose();
    _contextWindow.dispose();
    _maxOutputTokens.dispose();
    _inputModalities.dispose();
    super.dispose();
  }

  List<String> _tokens(String value, {required List<String> allowed}) => value
      .split(',')
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty && allowed.contains(item))
      .toSet()
      .toList();

  List<String> _unknownList(String key, List<String> known) {
    final value = _raw[key];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String &&
            item.trim().isNotEmpty &&
            !known.contains(item.trim().toLowerCase()))
          item.trim(),
    ];
  }

  List<String> _unknownInputModalities() {
    final modalities = _raw['modalities'];
    final value =
        modalities is Map ? modalities['input'] : _raw['inputModalities'];
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String &&
            item.trim().isNotEmpty &&
            !_allowedInputModalities.contains(item.trim().toLowerCase()))
          item.trim(),
    ];
  }

  Map<String, dynamic>? _buildModel({bool showError = false}) {
    final id = _id.text.trim();
    final kinds = _tokens(_kinds.text, allowed: _allowedKinds);
    final contextWindow = int.tryParse(_contextWindow.text.trim());
    final maxOutputTokens = int.tryParse(_maxOutputTokens.text.trim());
    final input =
        _tokens(_inputModalities.text, allowed: _allowedInputModalities);
    String? invalid;
    if (id.isEmpty) invalid = _text('模型 ID 必填。', 'Model ID is required.');
    if (invalid == null && kinds.isEmpty) {
      invalid = _text('至少选择一种 API 格式。', 'Select at least one API kind.');
    }
    if (invalid == null && (contextWindow == null || contextWindow <= 0)) {
      invalid =
          _text('上下文窗口必须是正整数。', 'Context window must be a positive integer.');
    }
    if (invalid == null &&
        !_contextOnly &&
        (maxOutputTokens == null || maxOutputTokens <= 0)) {
      invalid = _text('最大输出 Token 必须是正整数。',
          'Max output tokens must be a positive integer.');
    }
    if (invalid == null && !_contextOnly && !input.contains('text')) {
      invalid = _text('输入类型必须包含文本。', 'Input modalities must include text.');
    }
    if (invalid != null) {
      if (showError) setState(() => _error = invalid);
      return null;
    }
    final result = <String, dynamic>{
      ..._raw,
      'id': id,
      'kinds': [...kinds, ..._unknownList('kinds', _allowedKinds)],
      'defaultKind':
          kinds.contains(_preferredKind()) ? _preferredKind() : kinds.first,
      'contextWindow': contextWindow,
    };
    final name = _name.text.trim();
    if (name.isEmpty) {
      result.remove('name');
    } else {
      result['name'] = name;
    }
    if (!_contextOnly) {
      result['maxOutputTokens'] = maxOutputTokens;
      result['modalities'] = {
        'input': [...input, ..._unknownInputModalities()],
        'output': ['text'],
      };
      if (_modalitiesChanged) result['modalitiesConfigured'] = true;
    }
    return result;
  }

  bool get _contextOnly => widget.editMode == 'context-window-only';

  Future<void> _test() async {
    final modelRaw = _buildModel(showError: true);
    if (modelRaw == null || widget.model == null) return;
    final models = [
      for (final existing in widget.provider.models)
        identical(existing, widget.model) ? modelRaw : _cloneMap(existing.raw),
    ];
    await widget.connectivity.testModelConnectivity(
      provider: widget.provider,
      model: ModelEntry.fromRaw(modelRaw),
      draft: {'models': models},
    );
  }

  Future<void> _save() async {
    if (_saving || widget.readOnly) return;
    final model = _buildModel(showError: true);
    if (model == null || widget.onCommit == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final committed = await widget.onCommit!(model);
    if (!mounted) return;
    if (!committed) {
      setState(() {
        _saving = false;
        _error ??= _text('保存失败，请重试。', 'Save failed. Retry.');
      });
      return;
    }
    setState(() => _saving = false);
    widget.onSaved?.call();
  }

  Widget _choices({
    required TextEditingController controller,
    required List<String> choices,
    required String label,
    required bool readOnly,
    required bool lockFirst,
    bool modalities = false,
  }) {
    final selected = _tokens(controller.text, allowed: choices);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final choice in choices)
              FilterChip(
                label: Text(choice),
                selected: selected.contains(choice),
                onSelected: readOnly || (lockFirst && choice == choices.first)
                    ? null
                    : (value) {
                        final next = {...selected};
                        if (value) {
                          next.add(choice);
                        } else {
                          next.remove(choice);
                        }
                        if (lockFirst) next.add(choices.first);
                        controller.text = next.join(', ');
                        if (modalities) _modalitiesChanged = true;
                        setState(() => _error = null);
                      },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fieldReadOnly = widget.readOnly || _contextOnly;
    final canTest = widget.model != null && !widget.readOnly;
    return AlertDialog(
      title: Text(_text(widget.model == null ? '添加模型' : '编辑模型',
          widget.model == null ? 'Add model' : 'Edit model')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                readOnly: fieldReadOnly,
                decoration:
                    InputDecoration(labelText: _text('模型名称', 'Model name')),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _id,
                readOnly: fieldReadOnly,
                decoration:
                    InputDecoration(labelText: _text('模型 ID', 'Model ID')),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              _choices(
                controller: _kinds,
                choices: _allowedKinds,
                label: _text('API 格式', 'API kinds'),
                readOnly: fieldReadOnly,
                lockFirst: false,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contextWindow,
                readOnly: widget.readOnly,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: _text('上下文窗口', 'Context window')),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (!_contextOnly) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _maxOutputTokens,
                  readOnly: widget.readOnly,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: _text('最大输出 Token', 'Max output tokens')),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
                _choices(
                  controller: _inputModalities,
                  choices: _allowedInputModalities,
                  label: _text('输入类型', 'Input modalities'),
                  readOnly: widget.readOnly,
                  lockFirst: true,
                  modalities: true,
                ),
                const SizedBox(height: 6),
                Text(_text('输出类型：text（固定）', 'Output modalities: text (fixed)'),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (canTest) ...[
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: widget.connectivity,
                  builder: (context, _) {
                    final currentAttempt = widget.connectivity
                        .attemptFor(widget.provider.id, _id.text.trim());
                    final outcome = currentAttempt?.outcome;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ModelConnectivityButton(
                          modelId: _id.text,
                          hasApiKey: widget.provider.hasApiKey,
                          allowApiKeyless: widget.connectivity
                                      .dynamicHeadersResolver !=
                                  null &&
                              isZcodePlanProvider(
                                  widget.provider, widget.provider.raw),
                          pending: currentAttempt?.pending == true,
                          outcome: outcome,
                          useChinese: widget.useChinese,
                          onTest: _test,
                        ),
                        if (outcome != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ModelConnectivityResultPill(
                              outcome: outcome,
                              useChinese: widget.useChinese,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : widget.onCancel,
            child: Text(_text('取消', 'Cancel'))),
        FilledButton(
            onPressed: _saving || widget.readOnly ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_text('保存', 'Save'))),
      ],
    );
  }
}
