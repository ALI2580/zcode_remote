import 'package:flutter/material.dart';
import '../protocol/relay_client.dart';
import '../protocol/zemote_client.dart';
import '../state/client_preferences.dart';
import '../state/device_session.dart';
import 'official_icons.dart';
import 'theme.dart';

enum ConnectionBannerState {
  connected,
  connecting,
  recovering,
  failed,
  kicked,
  credentialsExpired,
  disconnected,
}

class ConnectionStatusSnapshot {
  const ConnectionStatusSnapshot({
    required this.state,
    this.reason,
    this.busy = false,
  });

  final ConnectionBannerState state;
  final String? reason;
  final bool busy;

  bool get healthy => state == ConnectionBannerState.connected;
}

ConnectionStatusSnapshot connectionStatusSnapshot(
    DeviceSession? session, BridgeSession? bridge) {
  final relay = session?.client?.relay;
  final bridgeReason = bridge?.degraded.value;
  if (session == null && bridge != null && bridgeReason == null) {
    return const ConnectionStatusSnapshot(
        state: ConnectionBannerState.connected);
  }
  if (session?.manuallyDisconnected == true ||
      relay?.state == RelayState.closed ||
      bridgeReason == 'user-disconnected') {
    return const ConnectionStatusSnapshot(
        state: ConnectionBannerState.disconnected);
  }
  final failureReason = session?.failureReason;
  if (failureReason == 'session-not-found' ||
      failureReason == 'session-expired' ||
      failureReason == 'invalid-mobile-connection') {
    return ConnectionStatusSnapshot(
        state: ConnectionBannerState.credentialsExpired, reason: failureReason);
  }
  // Official takeover copy (rog-official-kicked-screen.png): the relay KICKED
  // reason must be visible instead of a generic failure. Session-conflict
  // recovery keeps its own path; this only fires for the terminal kick.
  if (relay?.state == RelayState.kicked ||
      failureReason == 'kicked' ||
      bridgeReason == 'kicked') {
    return ConnectionStatusSnapshot(
        state: ConnectionBannerState.kicked,
        reason: failureReason ?? bridgeReason);
  }
  if (relay?.state == RelayState.error ||
      relay?.state == RelayState.kicked ||
      bridgeReason == 'kicked' ||
      bridgeReason == 'connection-failed') {
    return ConnectionStatusSnapshot(
        state: ConnectionBannerState.failed,
        reason: failureReason ?? bridgeReason);
  }
  if (bridgeReason != null && bridgeReason.startsWith('reopen-failed:')) {
    return ConnectionStatusSnapshot(
        state: ConnectionBannerState.failed, reason: 'reopen-failed');
  }
  if (bridgeReason != null) {
    return ConnectionStatusSnapshot(
        state: ConnectionBannerState.recovering, reason: bridgeReason);
  }
  switch (relay?.state) {
    case RelayState.paired:
      if (session?.bridgeRecovering == true) {
        return const ConnectionStatusSnapshot(
            state: ConnectionBannerState.recovering);
      }
      if (session != null && !session.connected) {
        return session.error != null
            ? ConnectionStatusSnapshot(
                state: ConnectionBannerState.failed,
                reason: session.failureReason)
            : const ConnectionStatusSnapshot(
                state: ConnectionBannerState.connecting);
      }
      return const ConnectionStatusSnapshot(
          state: ConnectionBannerState.connected);
    case RelayState.reconnecting:
      return const ConnectionStatusSnapshot(
          state: ConnectionBannerState.recovering);
    case RelayState.error:
      return ConnectionStatusSnapshot(
          state: ConnectionBannerState.failed, reason: failureReason);
    case RelayState.kicked:
      return const ConnectionStatusSnapshot(
          state: ConnectionBannerState.kicked, reason: 'kicked');
    case RelayState.connecting:
    case RelayState.authenticating:
    case RelayState.waiting:
      return const ConnectionStatusSnapshot(
          state: ConnectionBannerState.connecting);
    case RelayState.idle:
    case RelayState.closed:
    case null:
      if (session?.connecting == true) {
        return const ConnectionStatusSnapshot(
            state: ConnectionBannerState.connecting);
      }
      return const ConnectionStatusSnapshot(
          state: ConnectionBannerState.disconnected);
  }
}

String deviceConnectionStatus(BuildContext context, DeviceSession? session) {
  return switch (connectionStatusSnapshot(session, null).state) {
    ConnectionBannerState.connected => uiText(context, '已连接', 'Connected'),
    ConnectionBannerState.connecting => uiText(context, '连接中', 'Connecting'),
    ConnectionBannerState.recovering => uiText(context, '恢复中', 'Recovering'),
    ConnectionBannerState.credentialsExpired =>
      uiText(context, '需重新配对', 'Re-pair required'),
    ConnectionBannerState.failed =>
      uiText(context, '连接失败', 'Connection failed'),
    ConnectionBannerState.kicked =>
      uiText(context, '已被接管', 'Taken over'),
    ConnectionBannerState.disconnected =>
      uiText(context, '未连接', 'Not connected'),
  };
}

/// Shared non-modal connection notice for chat and settings. It deliberately
/// stays local to the affected page so the current task, draft, and scroll
/// position survive a relay/bridge interruption.
class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({
    super.key,
    this.session,
    this.bridge,
    this.onReconnect,
    this.onPairAgain,
    this.onCancel,
  });

  final DeviceSession? session;
  final BridgeSession? bridge;
  final Future<void> Function()? onReconnect;
  final Future<void> Function()? onPairAgain;
  final Future<void> Function()? onCancel;

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner> {
  bool _busy = false;
  int _actionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _attachListeners(widget);
  }

  void _attachListeners(ConnectionStatusBanner value) {
    value.session?.addListener(_onSourceChanged);
    value.bridge?.degraded.addListener(_onSourceChanged);
  }

  void _detachListeners(ConnectionStatusBanner value) {
    value.session?.removeListener(_onSourceChanged);
    value.bridge?.degraded.removeListener(_onSourceChanged);
  }

  void _onSourceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConnectionStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.bridge, widget.bridge)) {
      _actionGeneration++;
      _busy = false;
      _detachListeners(oldWidget);
      _attachListeners(widget);
    }
  }

  @override
  void dispose() {
    _detachListeners(widget);
    super.dispose();
  }

  Future<void> _run(Future<void> Function()? action,
      {bool allowWhileBusy = false}) async {
    if ((_busy && !allowWhileBusy) || action == null) return;
    final generation = ++_actionGeneration;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      // The owning session exposes the classified failure; keep this banner
      // visible and let that state render the next action.
    } finally {
      if (mounted && generation == _actionGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = connectionStatusSnapshot(widget.session, widget.bridge);
    if (snapshot.healthy) return const SizedBox.shrink();
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final recovering = snapshot.state == ConnectionBannerState.recovering;
    final connecting = snapshot.state == ConnectionBannerState.connecting;
    final retryingFailure = snapshot.state == ConnectionBannerState.failed &&
        snapshot.reason == 'reopen-failed';
    final credential =
        snapshot.state == ConnectionBannerState.credentialsExpired;
    final title = switch (snapshot.state) {
      ConnectionBannerState.connecting =>
        uiText(context, '正在连接远端桌面', 'Connecting to remote desktop'),
      ConnectionBannerState.recovering =>
        uiText(context, '连接中断，正在重新连接', 'Connection interrupted. Reconnecting'),
      ConnectionBannerState.credentialsExpired =>
        uiText(context, '配对已失效，请重新配对', 'Pairing expired. Pair again'),
      ConnectionBannerState.failed => retryingFailure
          ? uiText(context, '工作区恢复失败，仍在尝试',
              'Workspace recovery failed; still trying')
          : uiText(context, '连接失败', 'Connection failed'),
      ConnectionBannerState.kicked =>
        uiText(context, '已被其他设备接管', 'Taken over by another device'),
      ConnectionBannerState.disconnected =>
        uiText(context, '连接已断开', 'Connection disconnected'),
      ConnectionBannerState.connected => '',
    };
    final detail = switch (snapshot.state) {
      ConnectionBannerState.connecting => uiText(context, '正在建立握手，远端操作暂不可用。',
          'Handshake in progress. Remote actions are unavailable.'),
      ConnectionBannerState.recovering => uiText(
          context,
          '历史记录和草稿已保留，恢复完成后会同步状态。',
          'History and drafts are kept; state will sync after recovery.'),
      ConnectionBannerState.credentialsExpired => uiText(
          context,
          '请检查桌面端配对状态后重新连接。',
          'Check the desktop pairing state, then reconnect.'),
      ConnectionBannerState.kicked => uiText(
          context,
          '另一台远程控制设备已经接入，同一时间只能保留一个手机控制端。重新连接后本设备将重新接管。',
          'Another remote controller has connected; only one mobile controller is kept. Reconnect to take over again.'),
      ConnectionBannerState.failed => retryingFailure
          ? uiText(context, '远端操作暂不可用，系统仍在尝试恢复。',
              'Remote actions are unavailable; recovery is still being attempted.')
          : uiText(context, '远端操作暂不可用，请重试。',
              'Remote actions are unavailable. Try again.'),
      ConnectionBannerState.disconnected => uiText(
          context,
          '当前页面仍可阅读，重新连接后可继续操作。',
          'This page remains readable; reconnect to continue.'),
      ConnectionBannerState.connected => '',
    };
    return Container(
      key: const ValueKey('connection-status-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: credential ? ink.diffRemoved.withValues(alpha: .1) : ink.hover,
        border: Border.all(color: credential ? ink.diffRemoved : ink.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: recovering || connecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : LucideIcon('alert-triangle',
                    size: 16,
                    color: credential ? ink.diffRemoved : ink.subtlest),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(detail,
                    style: TextStyle(fontSize: 12, color: ink.subtlest)),
                if (widget.onReconnect != null || widget.onCancel != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if ((credential
                              ? (widget.onPairAgain ?? widget.onReconnect)
                              : widget.onReconnect) !=
                          null)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(credential
                                  ? (widget.onPairAgain ?? widget.onReconnect)
                                  : widget.onReconnect),
                          child: Text(_busy
                              ? uiText(context, '处理中…', 'Working…')
                              : credential
                                  ? uiText(context, '重新配对', 'Pair again')
                                  : uiText(context, '重新连接', 'Reconnect')),
                        ),
                      if ((recovering || connecting || retryingFailure) &&
                          widget.onCancel != null)
                        TextButton(
                          onPressed: () =>
                              _run(widget.onCancel, allowWhileBusy: true),
                          child: Text(uiText(context, '取消恢复', 'Cancel')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
