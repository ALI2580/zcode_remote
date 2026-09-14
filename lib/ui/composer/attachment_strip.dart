import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_attachments.dart';
import '../official_icons.dart';
import '../theme.dart';

class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip(
      {super.key, required this.attachments, this.locked = false});
  final ComposerAttachments attachments;
  final bool locked;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final entry in attachments.items)
                Container(
                    key: ValueKey('attachment-${entry.id}'),
                    constraints: const BoxConstraints(maxWidth: 260),
                    height: 48,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: ink.messageSurface,
                        border: Border.all(color: ink.border),
                        borderRadius: BorderRadius.circular(ZRadius.lg)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      InkWell(
                          onTap: () => _preview(context, entry),
                          child: entry.file.mime.startsWith('image/') &&
                                  entry.bytes != null
                              ? ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(ZRadius.md),
                                  child: Image.memory(entry.bytes!,
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                      cacheWidth: 96,
                                      errorBuilder: (_, __, ___) => LucideIcon(
                                          'paperclip',
                                          size: 16,
                                          color: ink.subtlest)))
                              : Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      color: ink.background,
                                      borderRadius:
                                          BorderRadius.circular(ZRadius.md)),
                                  child: Center(
                                      child: LucideIcon('paperclip',
                                          size: 16, color: ink.subtlest)))),
                      const SizedBox(width: 8),
                      Flexible(
                          child: InkWell(
                              onTap: () => _preview(context, entry),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.file.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            height: 1.2,
                                            fontWeight: FontWeight.w500,
                                            color: ink.text)),
                                    Text(
                                        _size(entry.bytes?.length ??
                                            entry.file.size),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            height: 1.2,
                                            color: ink.subtlest)),
                                  ]))),
                      if (_statusText(context, entry) != null)
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 112),
                            child: Text(_statusText(context, entry)!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    color: entry.phase == AttachmentPhase.failed
                                        ? ink.diffRemoved
                                        : ink.subtlest))),
                      if (entry.phase == AttachmentPhase.failed &&
                          !entry.tooLarge &&
                          !entry.unavailable)
                        _button(
                            context,
                            'refresh-cw',
                            uiText(context, '重试上传', 'Retry upload'),
                            locked ? null : () => attachments.retry(entry)),
                      _button(
                          context,
                          'x',
                          '${uiText(context, '移除附件', 'Remove attachment')} ${entry.file.name}',
                          locked ? null : () => attachments.remove(entry)),
                    ])),
            ])));
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : bytes >= 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '$bytes B';
  String? _statusText(BuildContext context, ComposerAttachment entry) =>
      switch (entry.phase) {
        AttachmentPhase.waitingSession => uiText(context, '准备中…', 'Preparing…'),
        AttachmentPhase.uploading =>
          '${uiText(context, '上传中', 'Uploading')} ${(entry.progress * 100).floor()}%',
        AttachmentPhase.ready => null,
        AttachmentPhase.failed => entry.unavailable
            ? uiText(context, '附件不可读取，请重新选择', 'Choose this file again')
            : entry.tooLarge
                ? uiText(context, '附件超过 20 MB', 'File exceeds 20 MB')
                : [
                    uiText(context, '上传失败', 'Upload failed'),
                    if (entry.uploadError != null) ': ${entry.uploadError}',
                  ].join(),
      };
  Widget _button(BuildContext context, String icon, String label,
          VoidCallback? onTap) =>
      Tooltip(
          message: label,
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                      child: LucideIcon(icon,
                          size: icon == 'x' ? 10 : 12,
                          color: icon == 'refresh-cw'
                              ? ZInk.of(Theme.of(context).colorScheme)
                                  .diffRemoved
                              : ZInk.of(Theme.of(context).colorScheme)
                                  .subtlest)))));
  Future<void> _preview(BuildContext context, ComposerAttachment entry) =>
      showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(entry.file.name),
                  content: SizedBox(
                      width: 560,
                      child: FutureBuilder<Uint8List>(
                          future: attachments.preview(entry),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Text(uiText(context, '附件不可读取，请重新选择',
                                  'Choose this file again'));
                            }
                            final bytes = snapshot.data;
                            if (bytes == null) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            return entry.file.mime.startsWith('image/')
                                ? Image.memory(bytes,
                                    cacheWidth: 1280,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Text(uiText(
                                        context,
                                        '无法预览此图片',
                                        'Image preview unavailable')))
                                : SingleChildScrollView(
                                    child: SelectableText((entry.file.mime
                                                .startsWith('text/') ||
                                            const [
                                              'application/json',
                                              'application/xml'
                                            ].contains(entry.file.mime))
                                        ? utf8.decode(
                                            bytes.take(64 * 1024).toList(),
                                            allowMalformed: true)
                                        : '${entry.file.mime}\n${_size(bytes.length)}'));
                          })),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(uiText(context, '关闭', 'Close')))
                  ]));
}

/// Official sent-message pills (`data-v4-user-input-attachments`): media is
/// grouped before file pills and uses the same 48px card skeleton without
/// composer remove/retry affordances.
class SentAttachmentPills extends StatelessWidget {
  const SentAttachmentPills({
    super.key,
    required this.attachments,
    this.readAttachment,
  });

  final List<Map<String, dynamic>> attachments;
  final Future<Uint8List> Function(String ref)? readAttachment;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final media = attachments
        .where((e) => '${e['mime'] ?? e['mimeType'] ?? ''}'
            .startsWith(RegExp('^(image/|video/)')))
        .toList();
    final files = attachments
        .where((e) => !'${e['mime'] ?? e['mimeType'] ?? ''}'
            .startsWith(RegExp('^(image/|video/)')))
        .toList();
    return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in [...media, ...files])
            if (media.contains(attachment) &&
                readAttachment != null &&
                attachment['ref'] is String)
              FutureBuilder<Uint8List>(
                  future: readAttachment!(attachment['ref'] as String),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    return Container(
                        key: ValueKey(
                            'sent-attachment-${attachment['ref'] ?? attachment['fileName'] ?? attachment.hashCode}'),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: ink.messageSurface,
                            border: Border.all(color: ink.border),
                            borderRadius: BorderRadius.circular(ZRadius.lg)),
                        child: bytes == null
                            ? Center(
                                child: LucideIcon('paperclip',
                                    size: 16, color: ink.subtlest))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(ZRadius.lg),
                                child: Image.memory(bytes,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                        child: LucideIcon('paperclip',
                                            size: 16, color: ink.subtlest)))));
                  })
            else
              Container(
                  key: ValueKey(
                      'sent-attachment-${attachment['ref'] ?? attachment['fileName'] ?? attachment.hashCode}'),
                  height: 48,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: ink.messageSurface,
                      border: Border.all(color: ink.border),
                      borderRadius: BorderRadius.circular(ZRadius.lg)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: ink.background,
                            borderRadius: BorderRadius.circular(ZRadius.md)),
                        child: Center(
                            child: LucideIcon('paperclip',
                                size: 16, color: ink.subtlest))),
                    const SizedBox(width: 8),
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                  '${attachment['fileName'] ?? attachment['filename'] ?? 'attachment'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      height: 1.2,
                                      fontWeight: FontWeight.w500,
                                      color: ink.text))),
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                  attachment['bytes'] is num
                                      ? _sentSize(
                                          (attachment['bytes'] as num).toInt())
                                      : '${attachment['mime'] ?? attachment['mimeType'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      height: 1.2,
                                      color: ink.subtlest))),
                        ]),
                  ])),
        ]);
  }

  String _sentSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : bytes >= 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '$bytes B';
}
