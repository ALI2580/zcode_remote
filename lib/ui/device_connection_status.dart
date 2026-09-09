import 'package:flutter/widgets.dart';
import '../protocol/relay_client.dart';
import '../state/client_preferences.dart';
import '../state/device_session.dart';

String deviceConnectionStatus(BuildContext context, DeviceSession? session) {
  if (session?.connected == true) return uiText(context, '已连接', 'Connected');
  if (session?.connecting == true) return uiText(context, '连接中', 'Connecting');
  if (session?.client?.relay.state == RelayState.reconnecting) {
    return uiText(context, '重连中', 'Reconnecting');
  }
  if (session?.error != null ||
      session?.client?.relay.state == RelayState.error) {
    return uiText(context, '连接失败', 'Connection failed');
  }
  return uiText(context, '未连接', 'Not connected');
}
