export 'device_info_stub.dart' if (dart.library.io) 'device_info_native.dart';

/// Device identity sent during relay auth and mobile-view-state updates.
///
/// The web client reports itself as a browser; Zemote identifies itself
/// honestly so the desktop can show the real connected client.
const zemoteAppName = 'zemote';

/// Real runtime platform (android / web / windows / ...), defaults to `web`
/// when unknown so the handshake stays valid on exotic targets.
