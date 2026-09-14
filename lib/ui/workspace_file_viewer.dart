import 'package:flutter/material.dart';

import '../protocol/conversation.dart';
import '../state/client_preferences.dart';
import 'code_renderer.dart';
import 'theme.dart';

class WorkspaceFileViewer extends StatefulWidget {
  const WorkspaceFileViewer({
    super.key,
    required this.transport,
    required this.path,
    required this.title,
  });

  final ConversationTransport transport;
  final String path;
  final String title;

  @override
  State<WorkspaceFileViewer> createState() => _WorkspaceFileViewerState();
}

class _WorkspaceFileViewerState extends State<WorkspaceFileViewer> {
  TextFileReadResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.transport.readTextFile(widget.path);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Dialog(
      backgroundColor: ink.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Expanded(
                    child: Text(widget.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(
                    tooltip: uiText(context, '关闭', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ])),
          Divider(height: 1, color: ink.border),
          Expanded(
            child: _error != null
                ? Center(child: Text('$_error'))
                : _result == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_result!.isBinary)
                                Text(uiText(context, '二进制文件无法显示',
                                    'Binary file cannot be displayed'))
                              else if (_result!.truncated)
                                Text(uiText(context, '文件过大，未加载全文',
                                    'File is too large; full content was not loaded'))
                              else
                                _result!.text?.isNotEmpty == true
                                    ? CodeViewer(
                                        source: _result!.text!,
                                        theme: CodeThemeCatalog.fromContext(
                                            context),
                                        fontSize: ClientPreferencesScope
                                                .maybeOf(context)
                                                ?.codeFontSize ??
                                            12,
                                        showLineNumbers:
                                            ClientPreferencesScope.maybeOf(
                                                        context)
                                                    ?.showLineNumbers ??
                                                true,
                                        wrapLongLines:
                                            ClientPreferencesScope.maybeOf(
                                                        context)
                                                    ?.wrapLongLines ??
                                                false)
                                    : Text(uiText(
                                        context, '文件为空', 'File is empty')),
                            ])),
          ),
        ]),
      ),
    );
  }
}
