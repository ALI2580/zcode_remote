import 'dart:async';

import 'package:flutter/material.dart';
import '../state/client_preferences.dart';

import 'theme.dart';
import '../voice/voice_download_state.dart';
import '../voice/voice_model_events.dart';
import '../voice/voice_model_readiness.dart';
import '../voice/voice_model_store.dart';
import '../voice/voice_models.dart';
import '../voice/voice_errors.dart';

class VoiceModelManager extends StatefulWidget {
  const VoiceModelManager({super.key, this.store, this.models});

  /// Defaults to the app-level shared store so an in-flight download keeps
  /// reporting its progress after the page is left and re-entered.
  final VoiceModelStore? store;
  final List<VoiceModelInfo>? models;

  @override
  State<VoiceModelManager> createState() => _VoiceModelManagerState();
}

class _VoiceModelManagerState extends State<VoiceModelManager> {
  late final VoiceModelStore _store;
  late final List<VoiceModelInfo> _models;
  final Map<String, bool> _busy = {};
  final Map<String, String> _errors = {};
  final Map<String, VoiceFailureKind> _errorKinds = {};
  Map<String, bool> _downloaded = {};
  Map<String, VoiceModelAvailability> _availability = {};
  String? _enabledId;
  int _refreshGeneration = 0;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? VoiceModelStore.instance;
    _models = widget.models ?? voiceModels;
    VoiceModelEvents.instance.addListener(_scheduleRefresh);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    VoiceModelEvents.instance.removeListener(_scheduleRefresh);
    _refreshDebounce?.cancel();
    super.dispose();
  }

  /// Download progress notifies once per chunk; coalescing the expensive
  /// availability scan keeps the visible bytes/percent updates flowing
  /// without re-reading every model directory for each event (U25).
  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    final downloaded = <String, bool>{};
    final availability = <String, VoiceModelAvailability>{};
    for (final model in _models) {
      try {
        final state = await voiceModelAvailability(_store, model);
        availability[model.id] = state;
        downloaded[model.id] = state == VoiceModelAvailability.downloaded ||
            state == VoiceModelAvailability.enabled;
      } catch (error) {
        downloaded[model.id] = false;
        availability[model.id] = VoiceModelAvailability.storageUnavailable;
        _errorKinds[model.id] = VoiceFailureKind.storageUnavailable;
        _errors[model.id] = '无法读取模型文件，请检查应用存储权限后重试：$error';
      }
    }
    final enabledId = availability.entries
        .where((entry) => entry.value == VoiceModelAvailability.enabled)
        .map((entry) => entry.key)
        .firstOrNull;
    if (!mounted || generation != _refreshGeneration) return;
    setState(() {
      _downloaded = downloaded;
      _availability = availability;
      _enabledId = enabledId;
    });
  }

  Future<void> _run(
      VoiceModelInfo model, Future<void> Function() action) async {
    if (_busy[model.id] == true) return;
    setState(() {
      _busy[model.id] = true;
      _errors.remove(model.id);
      _errorKinds.remove(model.id);
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorKinds[model.id] = error is VoiceModelStoreException
              ? error.kind
              : VoiceFailureKind.modelDownloadFailed;
          _errors[model.id] = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(model.id));
      }
      await _refresh();
    }
  }

  void _download(VoiceModelInfo model) {
    unawaited(_run(model, () => _store.download(model)));
  }

  void _repair(VoiceModelInfo model) {
    unawaited(_run(model, () async {
      await _store.delete(model);
      await _store.download(model);
    }));
  }

  void _delete(VoiceModelInfo model) {
    unawaited(_run(model, () => _store.delete(model)));
  }

  void _setEnabled(VoiceModelInfo model, bool enabled) {
    unawaited(_run(model,
        () => enabled ? _store.setEnabled(model) : _store.disable(model)));
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return ListenableBuilder(
        listenable: VoiceModelEvents.instance,
        builder: (context, _) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(uiText(context, '离线语音模型', 'Offline voice models'),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(
                  uiText(context, '模型保存在应用私有目录，下载失败不会标记为可用。',
                      'Models are stored in app-private storage. Failed downloads are not marked available.'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
              const SizedBox(height: 12),
              for (final model in _models) ..._card(context, ink, model),
            ]));
  }

  /// U25: per-phase download feedback. A known total shows bytes and a
  /// percentage; an unknown total shows received bytes with an indeterminate
  /// bar; extraction and verification get their own visible phases.
  List<Widget> _downloadFeedback(BuildContext context, VoiceModelInfo model) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final state = _store.downloadStates[model.id];
    if (state == null) {
      return const [LinearProgressIndicator()];
    }
    String label;
    double? percent = state.percent;
    switch (state.phase) {
      case VoiceDownloadPhase.downloading:
        final received = _formatBytes(state.received);
        if (state.total != null) {
          label = uiText(context, '下载中 $received / ${_formatBytes(state.total!)}',
              'Downloading $received / ${_formatBytes(state.total!)}');
        } else {
          label = uiText(
              context, '下载中 $received', 'Downloading $received');
        }
      case VoiceDownloadPhase.extracting:
        percent = null;
        label = uiText(context, '正在解压模型…', 'Extracting model…');
      case VoiceDownloadPhase.verifying:
        percent = null;
        label = uiText(context, '正在校验文件…', 'Verifying files…');
    }
    return [
      LinearProgressIndicator(value: percent),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(fontSize: 12, color: ink.subtlest)),
    ];
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  List<Widget> _card(
      BuildContext context, InkTokens ink, VoiceModelInfo model) {
    final busy = _busy[model.id] == true;
    final downloaded = _downloaded[model.id] == true;
    final enabled = _enabledId == model.id;
    final availability = _availability[model.id] ??
        (downloaded
            ? VoiceModelAvailability.downloaded
            : VoiceModelAvailability.notDownloaded);
    final error = _errors[model.id];
    final errorKind = _errorKinds[model.id];
    final english = Localizations.localeOf(context).languageCode != 'zh';
    final errorSummary = voiceFailureMessage(errorKind, english: english) ??
        uiText(context, '模型操作失败，请重试', 'Model operation failed. Try again.');
    final children = <Widget>[
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: ink.surface,
              border: Border.all(color: ink.border),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(model.name,
                      style: const TextStyle(fontWeight: FontWeight.w500))),
              Text(
                  switch (availability) {
                    VoiceModelAvailability.enabled =>
                      uiText(context, '已启用', 'Enabled'),
                    VoiceModelAvailability.downloaded =>
                      uiText(context, '已下载但未启用', 'Downloaded'),
                    VoiceModelAvailability.corrupt =>
                      uiText(context, '模型损坏', 'Corrupt model'),
                    VoiceModelAvailability.storageUnavailable =>
                      uiText(context, '存储不可用', 'Storage unavailable'),
                    VoiceModelAvailability.notDownloaded =>
                      uiText(context, '未下载', 'Not downloaded'),
                  },
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
            ]),
            const SizedBox(height: 6),
            Text(
                english
                    ? (model.descriptionEn ?? model.description)
                    : model.description,
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
            const SizedBox(height: 6),
            Text(
                english
                    ? (model.languagesEn ?? model.languages)
                    : model.languages,
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else ...[
                if (availability == VoiceModelAvailability.corrupt) ...[
                  FilledButton(
                      onPressed: () => _repair(model),
                      child: Text(uiText(context, '重新下载', 'Download again'))),
                ] else if (availability ==
                    VoiceModelAvailability.storageUnavailable) ...[
                  FilledButton(
                      onPressed: _refresh,
                      child: Text(uiText(context, '重试', 'Retry'))),
                ] else if (downloaded) ...[
                  FilledButton.tonal(
                      onPressed: enabled
                          ? () => _setEnabled(model, false)
                          : () => _setEnabled(model, true),
                      child: Text(enabled
                          ? uiText(context, '停用', 'Disable')
                          : uiText(context, '启用', 'Enable'))),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: () => _delete(model),
                      child: Text(uiText(context, '删除', 'Delete'))),
                ] else ...[
                  if (error == null) ...[
                    FilledButton(
                        onPressed: () => _download(model),
                        child: Text(uiText(context, '下载', 'Download'))),
                    const SizedBox(width: 8),
                  ] else ...[
                    FilledButton(
                        onPressed: () => _download(model),
                        child: Text(uiText(context, '重试', 'Retry'))),
                    const SizedBox(width: 8),
                  ],
                ],
              ],
              if (busy)
                OutlinedButton(
                    onPressed: () => _store.cancelDownload(model),
                    child: Text(uiText(context, '取消', 'Cancel'))),
            ]),
            if (busy) ...[
              const SizedBox(height: 12),
              ..._downloadFeedback(context, model),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(errorSummary,
                  style: TextStyle(color: ink.diffRemoved, fontSize: 12)),
              if (error != errorSummary) ...[
                const SizedBox(height: 3),
                Text(error,
                    style: TextStyle(color: ink.subtlest, fontSize: 11)),
              ],
            ],
          ])),
    ];
    return children;
  }
}
