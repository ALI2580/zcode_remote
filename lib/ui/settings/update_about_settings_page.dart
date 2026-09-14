import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../update/app_version.dart';
import '../../update/update_channel.dart';
import '../../update/update_checker.dart';
import '../../update/update_downloader.dart';
import '../../state/client_preferences.dart';
import '../theme.dart';

/// "更新与关于" settings section content, extracted from
/// `settings_center_page.dart` (S1). Owns the full update-check and
/// in-app-download lifecycle: check state, error, release info and the
/// [UpdateDownloader] instance. Rendered inside the settings ListView, so
/// the column keeps loose-width left alignment like the previous inline
/// children.
class UpdateAboutSettingsPage extends StatefulWidget {
  const UpdateAboutSettingsPage({super.key});

  @override
  State<UpdateAboutSettingsPage> createState() =>
      _UpdateAboutSettingsPageState();
}

class _UpdateAboutSettingsPageState extends State<UpdateAboutSettingsPage> {
  bool _checking = false;
  String? _updateError;
  UpdateInfo? _update;
  UpdateDownloader? _downloader;

  @override
  void initState() {
    super.initState();
    unawaited(updateChannelSettings.load().then((_) {
      if (mounted) setState(() {});
    }));
  }

  void _startDownload() {
    final assets = _update?.assets ?? [];
    if (assets.isEmpty) return;
    final asset = assets.first;
    _downloader ??= UpdateDownloader();
    _downloader!.download(url: asset.apkUrl);
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateError = null;
    });
    try {
      final result = await checkForUpdates();
      if (mounted) setState(() => _update = result);
    } catch (_) {
      if (mounted) {
        setState(() => _updateError = uiText(
            context, '检查失败，请稍后重试', 'Could not check for updates. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _downloader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ZcodeRemote $appVersion ($appBuildNumber)',
          style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 20),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(uiText(context, '接收 Beta 更新', 'Receive beta updates')),
          value: updateChannelSettings.receiveBetaUpdates,
          onChanged: (value) async {
            await updateChannelSettings.setReceiveBetaUpdates(value);
            if (mounted) setState(() {});
          }),
      const SizedBox(height: 12),
      Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
              onPressed: _checking ? null : _checkUpdate,
              child: Text(_checking
                  ? uiText(context, '正在检查…', 'Checking…')
                  : uiText(context, '检查更新', 'Check for updates')))),
      if (_updateError != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_updateError!,
                style: TextStyle(color: ink.diffRemoved))),
      if (_update != null) ...[
        const SizedBox(height: 20),
        Text(_update!.isNewer
            ? uiText(context, '发现新版本 ${_update!.latestVersion}',
                'New version ${_update!.latestVersion}')
            : uiText(context, '当前已是最新版本', 'You are up to date')),
        if (_update!.body?.trim().isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(_update!.body!)),
        if (_update!.isNewer) ...[
          Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, children: [
                TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: _update!.releaseUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(uiText(context, '下载页面地址已复制',
                                'Download page copied'))));
                      }
                    },
                    child: Text(
                        uiText(context, '复制下载页面地址', 'Copy download page'))),
                ListenableBuilder(
                    listenable: _downloader ?? Listenable.merge([]),
                    builder: (context, _) {
                      final dl = _downloader;
                      final prog = dl?.progress;
                      return FilledButton(
                          onPressed: _update!.assets.isEmpty ||
                                  (dl?.isBusy ?? false)
                              ? null
                              : _startDownload,
                          child: Text((prog?.state ==
                                      DownloadState.downloading ||
                                  prog?.state == DownloadState.verifying)
                              ? uiText(context, '下载中…', 'Downloading…')
                              : uiText(context, '下载 APK', 'Download APK')));
                    }),
              ])),
          if (_downloader != null)
            ListenableBuilder(
                listenable: _downloader!,
                builder: (context, _) {
                  final prog = _downloader!.progress;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (prog.state == DownloadState.downloading &&
                            prog.fraction != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(
                                  value: prog.fraction)),
                        if (prog.state == DownloadState.verifying)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                  uiText(context, '校验中…', 'Verifying…'))),
                        if (prog.state == DownloadState.done &&
                            prog.filePath != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  uiText(context, '已下载到 ${prog.filePath}',
                                      'Downloaded to ${prog.filePath}'),
                                  style: TextStyle(
                                      fontSize: 12, color: ink.subtlest))),
                        if (prog.state == DownloadState.failed &&
                            prog.error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(prog.error!,
                                  style:
                                      TextStyle(color: ink.diffRemoved))),
                      ]);
                }),
        ],
      ],
    ]);
  }
}
