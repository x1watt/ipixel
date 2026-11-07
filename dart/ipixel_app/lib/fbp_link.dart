import 'dart:async';
import 'dart:typed_data';

// flutter_blue_plus_windows = flutter_blue_plus + Windows backend (same API everywhere).
import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

/// [BleLink] on flutter_blue_plus (Android, iOS, macOS, Linux, Web; Windows via
/// flutter_blue_plus_windows).
class FbpLink implements BleLink {
  final BluetoothDevice device;
  final BluetoothCharacteristic _write, _notify;
  final _ctrl = StreamController<Uint8List>.broadcast();
  StreamSubscription<List<int>>? _sub;

  FbpLink._(this.device, this._write, this._notify);

  static Guid _g(String u) => Guid(u);

  static Future<FbpLink> connect(BluetoothDevice device) async {
    await device.connect(mtu: 512, timeout: const Duration(seconds: 15));
    final services = await device.discoverServices();
    final svc = services.firstWhere((s) => s.uuid == _g(IPixelUuids.service),
        orElse: () => throw IPixelException('service 0xFA not found'));
    BluetoothCharacteristic ch(String u) => svc.characteristics.firstWhere((c) => c.uuid == _g(u));
    final link = FbpLink._(device, ch(IPixelUuids.write), ch(IPixelUuids.notify));
    link._sub = link._notify.onValueReceived.listen((v) => link._ctrl.add(Uint8List.fromList(v)));
    device.cancelWhenDisconnected(link._sub!);
    await link._notify.setNotifyValue(true);
    return link;
  }

  /// Scan for displays by name prefix / manufacturer data.
  static Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map((rs) => rs
        .where((r) => IPixelAdvert.matches(
            name: r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName,
            manufacturerData: r.advertisementData.manufacturerData))
        .toList());
  }

  @override
  Stream<Uint8List> get notifications => _ctrl.stream;

  @override
  int get maxWriteLength => device.mtuNow - 3;

  @override
  Future<void> write(Uint8List data, {bool withResponse = true}) =>
      _write.write(data, withoutResponse: !withResponse);

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await device.disconnect();
  }
}
