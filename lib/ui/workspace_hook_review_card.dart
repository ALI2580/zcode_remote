import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/interaction_requests.dart';
import 'theme.dart';

/// The non-blocking admission banner. Official JS renders the same
/// `pendingCount / Review / Dismiss` surface while review trust itself opens
/// the hooks settings; this mobile surface keeps the immutable review items
/// adjacent until the full remote settings page is migrated.
class WorkspaceHookReviewBanner extends StatelessWidget {
  const WorkspaceHookReviewBanner({
    super.key,
    required this.controller,
    this.onOpenHooks,
  });

  final WorkspaceHookReviewController controller;
  final VoidCallback? onOpenHooks;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final request = controller.active;
        final admission = controller.admission;
        if (request == null && admission == null) {
          return const SizedBox.shrink();
        }
        final ink = ZInk.of(Theme.of(context).colorScheme);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ink.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    uiText(
                      context,
                      admission != null
                          ? '${controller.admissionCount} 个工作区 Hook 待审核，本会话暂未启用'
                          : '${controller.pendingCount} 个 Hook 需要审查',
                      admission != null
                          ? '${controller.admissionCount} workspace hook(s) pending review; disabled for this session'
                          : '${controller.pendingCount} hooks need review',
                    ),
                    style: TextStyle(fontSize: 14, color: ink.text),
                  ),
                ),
                FilledButton(
                  onPressed: admission != null
                      ? () {
                          onOpenHooks?.call();
                          unawaited(controller.requestAdmissionReview());
                        }
                      : () => unawaited(
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => WorkspaceHookReviewSheet(
                                controller: controller,
                                request: request!,
                              ),
                            ),
                          ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Text(uiText(
                      context, admission != null ? '去审核' : '审查', 'Review')),
                ),
                TextButton(
                  onPressed: admission != null
                      ? controller.dismissAdmission
                      : () => controller.dismiss(request!),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Text(uiText(context, '忽略', 'Dismiss')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class WorkspaceHookReviewSheet extends StatefulWidget {
  const WorkspaceHookReviewSheet({
    super.key,
    required this.controller,
    required this.request,
  });

  final WorkspaceHookReviewController controller;
  final Map<String, dynamic> request;

  @override
  State<WorkspaceHookReviewSheet> createState() =>
      _WorkspaceHookReviewSheetState();
}

class _WorkspaceHookReviewSheetState extends State<WorkspaceHookReviewSheet> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(WorkspaceHookReviewSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_closed) return;
    final interactionId = '${widget.request['interactionId'] ?? ''}';
    if (!widget.controller.state.pendingInteractions
        .any((item) => '${item['interactionId'] ?? ''}' == interactionId)) {
      _closed = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final payload =
        (widget.request['payload'] as Map?)?.cast<String, dynamic>() ??
            const {};
    final summary = (payload['summary'] as Map?)?.cast<String, dynamic>();
    final busy = widget.controller.resolvingOperationIds.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(
            color: ink.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: ink.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${payload['workspaceLabel'] ?? uiText(context, '工作区 Hook 审查', 'Workspace hook review')}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ink.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      uiText(
                        context,
                        '${summary?['eventCount'] ?? 0} 类事件 · ${summary?['hookCount'] ?? 0} 个 Hook · ${summary?['pendingCount'] ?? 0} 个待信任',
                        '${summary?['eventCount'] ?? 0} events · ${summary?['hookCount'] ?? 0} hooks · ${summary?['pendingCount'] ?? 0} pending',
                      ),
                      style: TextStyle(fontSize: 12, color: ink.subtlest),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.controller.items(widget.request).length,
                  itemBuilder: (context, index) {
                    final item = widget.controller.items(widget.request)[index];
                    return _item(context, item, busy);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, Map<String, dynamic> item, bool busy) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final reviewItemId = '${item['reviewItemId'] ?? ''}';
    final trustState = '${item['trustState'] ?? ''}';
    final actionable = const {
      'pending_trust',
      'revoked',
      'stale_digest',
    }.contains(trustState);
    final failure = widget.controller
        .failureFor('${widget.request['interactionId']}', reviewItemId);
    final operationId = widget.controller
        .operationIdFor('${widget.request['interactionId']}', reviewItemId);
    final itemBusy =
        widget.controller.resolvingOperationIds.contains(operationId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item['displayName'] ?? item['displayCommand'] ?? reviewItemId}',
            style: TextStyle(fontSize: 14, color: ink.text),
          ),
          const SizedBox(height: 4),
          Text(
            '${item['event'] ?? ''} · ${item['type'] ?? ''} · $trustState',
            style: TextStyle(fontSize: 12, color: ink.subtlest),
          ),
          if ('${item['displayCommand'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${item['displayCommand']}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: ink.subtlest,
                ),
              ),
            ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                uiText(
                  context,
                  '信任未受理：${failure.status ?? failure.reasonCode ?? failure.error ?? ''}',
                  'Trust was not accepted: ${failure.status ?? failure.reasonCode ?? failure.error ?? ''}',
                ),
                style: TextStyle(fontSize: 12, color: ink.diffRemoved),
              ),
            ),
          if (actionable)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed:
                    busy || itemBusy ? null : () => unawaited(_trust(item)),
                child: Text(uiText(context, '信任', 'Trust')),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _trust(Map<String, dynamic> item) async {
    final ok = await widget.controller.trustItem(widget.request, item);
    if (ok && mounted) {
      _closed = true;
      Navigator.of(context).pop();
    }
  }
}
