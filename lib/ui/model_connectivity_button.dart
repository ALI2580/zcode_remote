import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/model_connectivity.dart';
import 'official_icons.dart';
import 'theme.dart';

/// Official Test-model affordance (js-1 model row, 2026-09-13 extraction):
/// a ghost icon button using the official `unplug` glyph; pending swaps to a
/// same-size spinner. The result never lives inside the button — the official
/// row renders it as an inline pill below the model row
/// (`ModelConnectivityResultPill`).
class ModelConnectivityButton extends StatelessWidget {
  const ModelConnectivityButton({
    super.key,
    required this.modelId,
    this.hasApiKey = false,
    this.allowApiKeyless = false,
    this.pending = false,
    this.outcome,
    this.onTest,
    this.useChinese = false,
  });

  final String modelId;
  final bool hasApiKey;
  final bool allowApiKeyless;
  final bool pending;
  final ModelConnectivityOutcome? outcome;
  final FutureOr<void> Function()? onTest;
  final bool useChinese;

  bool get canTest =>
      onTest != null &&
      modelId.trim().isNotEmpty &&
      (hasApiKey || allowApiKeyless);

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final icon = pending
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2))
        : LucideIcon('unplug', size: 15, color: ink.subtlest);
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      tooltip: uiText(context, '测试模型', 'Test model'),
      onPressed: canTest && !pending
          ? () {
              final callback = onTest;
              if (callback != null) {
                unawaited(() async {
                  await callback();
                }());
              }
            }
          : null,
      icon: icon,
    );
  }
}

/// Official result presentation (`settings.modelProvider.testModel.*`): a
/// rounded pill below the model row — success uses the confirmation token
/// pair, failure the destructive pair, and the raw failure reason is shown
/// verbatim (official `lVt` keeps the agent-provided message).
class ModelConnectivityResultPill extends StatelessWidget {
  const ModelConnectivityResultPill({
    super.key,
    required this.outcome,
    this.useChinese = false,
  });

  final ModelConnectivityOutcome outcome;
  final bool useChinese;

  String _label(BuildContext context) {
    if (outcome.success) {
      return useChinese ? '连接成功！' : 'Connected!';
    }
    final reason = outcome.failureReason?.trim() ?? '';
    if (reason.isEmpty) {
      if (outcome.noEndpointResult) {
        return useChinese ? '未配置 endpoint' : 'No endpoint configured';
      }
      return useChinese ? '连接失败' : 'Connection failed';
    }
    return useChinese ? '连接失败：$reason' : 'Connection failed: $reason';
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final success = outcome.success;
    final color = success ? ink.confirmationText : ink.diffRemoved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: success
            ? ink.confirmationSurface
            : ink.diffRemoved.withValues(alpha: .1),
        border: Border.all(
            color: success
                ? ink.confirmationText.withValues(alpha: .3)
                : ink.diffRemoved.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label(context),
        softWrap: true,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}
