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
                    constraints: const BoxConstraints(maxWidth: 224),
                    padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
                    decoration: BoxDecoration(
                        color: ink.messageSurface,
                        border: Border.all(
                            color: entry.phase == AttachmentPhase.failed
                                ? ink.diffRemoved
                                : ink.border),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      InkWell(
                          onTap: () => _preview(context, entry),
                          child: entry.file.mime.startsWith('image/') &&
                                  entry.bytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.memory(entry.bytes!,
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                      cacheWidth: 96,
                                      errorBuilder: (_, __, ___) => LucideIcon(
                                          'paperclip',
                                          size: 24,
                                          color: ink.subtlest)))
                              : LucideIcon('paperclip',
                                  size: 24, color: ink.subtlest)),
                      const SizedBox(width: 6),
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
                                            fontSize: 12, color: ink.text)),
                                    Text(
                                        switch (entry.phase) {
                                          AttachmentPhase.waitingSession =>
                                            uiText(
                                                context, '准备中…', 'Preparing…'),
                                          AttachmentPhase.uploading =>
                                            '${uiText(context, '上传中', 'Uploading')} ${(entry.progress * 100).floor()}%',
                                          AttachmentPhase.ready => _size(
                                              entry.bytes?.length ??
                                                  entry.file.size),
                                          AttachmentPhase.failed =>
                                            entry.unavailable
                                                ? uiText(
                                                    context,
                                                    '附件不可读取，请重新选择',
                                                    'Choose this file again')
                                                : entry.tooLarge
                                                    ? uiText(
                                                        context,
                                                        '附件超过 20 MB',
                                                        'File exceeds 20 MB')
                                                    : uiText(context, '上传失败',
                                                        'Upload failed'),
                                        },
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: entry.phase ==
                                                    AttachmentPhase.failed
                                                ? ink.diffRemoved
                                                : ink.subtlest)),
                                  ]))),
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
  Widget _button(BuildContext context, String icon, String label,
          VoidCallback? onTap) =>
      Tooltip(
          message: label,
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                  width: 26,
                  height: 28,
                  child: Center(
                      child: LucideIcon(icon,
                          size: 14,
                          color: ZInk.of(Theme.of(context).colorScheme)
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
