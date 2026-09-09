import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

class RemoteProfile {
  const RemoteProfile({required this.name, this.avatarUrl});
  final String name;
  final String? avatarUrl;
  static RemoteProfile? parse(dynamic result) {
    if (result is! Map ||
        result['status'] != 'authenticated' ||
        result['userInfo'] is! Map) {
      return null;
    }
    final info = result['userInfo'] as Map;
    final name = '${info['displayName'] ?? info['username'] ?? 'ZCode'}'.trim();
    final avatar =
        info['avatarUrl'] is String ? info['avatarUrl'] as String : null;
    return RemoteProfile(
        name: name.isEmpty ? 'ZCode' : name,
        avatarUrl: avatar != null && Uri.tryParse(avatar)?.scheme == 'https'
            ? avatar
            : null);
  }

  static Future<RemoteProfile?> load(BridgeSession bridge) async =>
      parse(await bridge.channels.call(
          Channels.oauth, 'restoreCachedSessionState', const [],
          timeout: const Duration(seconds: 12)));
}
