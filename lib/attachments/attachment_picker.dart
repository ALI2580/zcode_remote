import 'package:flutter/services.dart';
import '../state/composer_attachments.dart';

const _channel = MethodChannel('zcode_remote/attachments');
Future<void> cancelAttachmentPick() =>
    _channel.invokeMethod<void>('cancelPick');
Future<List<PickedAttachment>> pickAttachments() async {
  final result = await _channel.invokeListMethod<dynamic>('pick');
  return [
    for (final item in (result ?? []).whereType<Map>())
      if (item['name'] is String) _fromMetadata(item),
  ];
}

PickedAttachment _fromMetadata(Map item, {bool? available}) {
  final token = item['token'], digest = item['sha256'];
  final valid = token is String &&
      RegExp(r'^[a-f0-9-]{36}$').hasMatch(token) &&
      digest is String &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(digest);
  final recovery =
      valid ? <String, dynamic>{'token': token, 'sha256': digest} : null;
  final tooLarge = item['size'] is num && item['size'] > 20 * 1024 * 1024;
  return PickedAttachment(
      name: item['name'] as String,
      mime: item['mime'] is String ? item['mime'] : 'application/octet-stream',
      size: item['size'] is num ? (item['size'] as num).toInt() : 0,
      recovery: recovery,
      unavailable: !tooLarge && (available == false || !valid),
      read: () async {
        try {
          if (!valid) throw const AttachmentUnavailable();
          final bytes =
              await _channel.invokeMethod<Uint8List>('read', recovery);
          if (bytes == null) throw const AttachmentUnavailable();
          return bytes;
        } catch (_) {
          throw const AttachmentUnavailable();
        }
      });
}

Future<PickedAttachment> restorePickedAttachment(
    Map<String, dynamic> metadata) async {
  bool available = false;
  if (metadata['token'] is String) {
    try {
      available = await _channel
              .invokeMethod<bool>('exists', {'token': metadata['token']}) ==
          true;
    } catch (_) {/* Missing file is retained visibly for re-selection. */}
  }
  return _fromMetadata(metadata, available: available);
}

Future<void> prunePickedAttachments(Iterable<String> retainedTokens) async {
  await _channel
      .invokeMethod<void>('prune', {'retained': retainedTokens.toList()});
}
