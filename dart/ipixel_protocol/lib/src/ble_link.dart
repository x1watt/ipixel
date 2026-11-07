import 'dart:typed_data';

/// Minimal transport an app must provide (one per BLE stack).
///
/// Implementations: flutter_blue_plus (mobile/desktop), BlueZ (Linux CLI), etc.
abstract class BleLink {
  /// Write one ATT value to the FA02 characteristic. [withResponse] = write request.
  Future<void> write(Uint8List data, {bool withResponse = true});

  /// Notifications from the FA03 characteristic (must already be subscribed).
  Stream<Uint8List> get notifications;

  /// Max bytes per write (negotiated ATT MTU - 3). Request MTU 512 when possible.
  int get maxWriteLength;

  Future<void> disconnect();
}
