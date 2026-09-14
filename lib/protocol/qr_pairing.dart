import 'connection_params.dart';

/// Cleans and validates a raw QR payload as a remote-control link.
///
/// Camera scanners and sharing sheets frequently add noise around the
/// encoded URL: surrounding whitespace, BOM, wrapping quotes or a trailing
/// newline. The desktop also prints the link in copy blocks where a trailing
/// slash can appear. Anything that does not parse as a remote-control URL
/// returns null so callers can show an "unrecognized QR code" error instead
/// of storing a broken pairing.
String? sanitizeRemoteControlPayload(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  // BOM and zero-width characters survive Trim() and break Uri.parse.
  text = text.replaceAll('\ufeff', '').replaceAll('\u200b', '').trim();
  for (final quote in ["'", '"', '`']) {
    if (text.length >= 2 && text.startsWith(quote) && text.endsWith(quote)) {
      text = text.substring(1, text.length - 1).trim();
    }
  }
  // Angle brackets / markdown autolinks around a pasted or QR-encoded URL.
  if (text.length >= 2 && text.startsWith('<') && text.endsWith('>')) {
    text = text.substring(1, text.length - 1).trim();
  }
  final params = ZemoteConnectionParams.parse(text);
  if (params == null || params.source.host.isEmpty) return null;
  return text;
}
