import 'package:zcode_remote/protocol/relay_client.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'fake_workspace.dart';

class _PairedReviewRelay extends RelayClient {
  _PairedReviewRelay(super.params);
  @override
  RelayState get state => RelayState.paired;
}

/// A synthetic paired relay; no socket is opened by FakeDeviceSession.connect.
class ReviewConnectedSession extends FakeDeviceSession {
  ReviewConnectedSession(super.params, super.bridge, {super.gate});
  late final reviewClient =
      ZemoteClient(params, relayClient: _PairedReviewRelay(params));
  @override
  ZemoteClient get client => reviewClient;
}
