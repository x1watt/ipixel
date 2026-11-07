import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

/// A display seen while scanning.
class BlueZDisplay {
  final BlueZDevice device;
  BlueZDisplay(this.device);
  String get address => device.address;
  String get name => device.name.isNotEmpty ? device.name : device.alias;
  int get rssi => device.rssi;
  IPixelAdvert? get advert {
    final m = device.manufacturerData.entries.where((e) => e.key.id == ipixelManufacturerIdLE).firstOrNull;
    return m == null ? null : IPixelAdvert.fromManufacturerData(m.value);
  }
}

bool _isDisplay(BlueZDevice d) => IPixelAdvert.matches(
    name: d.name, manufacturerData: {for (final e in d.manufacturerData.entries) e.key.id: e.value});

/// Scans for iPixel displays through BlueZ. Emits the current list on every change.
class BlueZScanner {
  final BlueZClient client = BlueZClient();
  BlueZAdapter? _adapter;
  final _ctrl = StreamController<List<BlueZDisplay>>.broadcast();
  final _subs = <StreamSubscription>[];

  Stream<List<BlueZDisplay>> get results => _ctrl.stream;

  List<BlueZDisplay> get current => client.devices.where(_isDisplay).map(BlueZDisplay.new).toList()
    ..sort((a, b) => b.rssi.compareTo(a.rssi));

  Future<void> start() async {
    await client.connect();
    if (client.adapters.isEmpty) throw IPixelException('no Bluetooth adapter');
    _adapter = client.adapters.first;
    // Only emit when the set of displays (or their RSSI bucket) changes, max twice a second.
    String sig(List<BlueZDisplay> l) => l.map((d) => '${d.address}/${d.rssi ~/ 5}').join(',');
    var lastSig = '';
    Timer? pending;
    void emit([_]) {
      if (pending != null) return;
      pending = Timer(const Duration(milliseconds: 500), () {
        pending = null;
        final cur = current;
        final s = sig(cur);
        if (s != lastSig && !_ctrl.isClosed) {
          lastSig = s;
          _ctrl.add(cur);
        }
      });
    }
    _subs
      ..add(client.deviceAdded.listen((d) {
        emit();
        if (_isDisplay(d)) _subs.add(d.propertiesChanged.listen(emit));
      }))
      ..add(client.deviceRemoved.listen(emit));
    for (final d in client.devices.where(_isDisplay)) {
      _subs.add(d.propertiesChanged.listen(emit));
    }
    emit();
    if (!_adapter!.discovering) await _adapter!.startDiscovery();
  }

  Future<void> stopDiscovery() async {
    try {
      if (_adapter?.discovering ?? false) await _adapter!.stopDiscovery();
    } catch (_) {}
  }

  /// Connect to a found display. The scanner's D-Bus client is handed over to the link.
  Future<BlueZLink> connect(BlueZDisplay d) async {
    await stopDiscovery();
    return BlueZLink.attach(client, d.device, ownsClient: false);
  }

  Future<void> close() async {
    await stopDiscovery();
    for (final s in _subs) {
      await s.cancel();
    }
    await _ctrl.close();
    await client.close();
  }
}

/// [BleLink] over BlueZ D-Bus (Linux, no Flutter needed).
class BlueZLink implements BleLink {
  /// Write socket from BlueZ AcquireWrite: ~8x faster than one D-Bus WriteValue per piece.
  /// While held, BlueZ refuses WriteValue, so every write goes through it (write-without-response;
  /// the panel's own ack notifications still confirm delivery).
  RawSocket? _sock;
  int _sockMtu = 23;

  final BlueZClient client;
  final BlueZDevice device;
  final BlueZGattCharacteristic _write, _notify;
  final _ctrl = StreamController<Uint8List>.broadcast();
  StreamSubscription? _sub;

  final bool _ownsClient;

  BlueZLink._(this.client, this.device, this._write, this._notify, this._ownsClient);

  /// Scan (if needed) and connect to [address], or to the first LED_BLE display when null.
  static Future<BlueZLink> connect({String? address, Duration scan = const Duration(seconds: 8)}) async {
    final client = BlueZClient();
    await client.connect();
    if (client.adapters.isEmpty) throw IPixelException('no Bluetooth adapter');
    final adapter = client.adapters.first;

    bool isTarget(BlueZDevice d) => address != null
        ? d.address.toUpperCase() == address.toUpperCase()
        : IPixelAdvert.matches(
            name: d.name,
            manufacturerData: {for (final e in d.manufacturerData.entries) e.key.id: e.value});

    var dev = client.devices.where(isTarget).firstOrNull;
    if (dev == null) {
      final found = Completer<BlueZDevice>();
      final s = client.deviceAdded.listen((d) {
        if (isTarget(d) && !found.isCompleted) found.complete(d);
      });
      await adapter.startDiscovery();
      try {
        dev = await found.future.timeout(scan);
      } on TimeoutException {
        throw IPixelException('display not found');
      } finally {
        await s.cancel();
        await adapter.stopDiscovery();
      }
    }
    return attach(client, dev, ownsClient: true);
  }

  /// Connect an already-known BlueZ device and subscribe to notifications.
  static Future<BlueZLink> attach(BlueZClient client, BlueZDevice dev, {required bool ownsClient}) async {
    if (!dev.connected) await dev.connect();
    for (var i = 0; !dev.servicesResolved && i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final svc = dev.gattServices.firstWhere((s) => s.uuid.toString() == IPixelUuids.service,
        orElse: () => throw IPixelException('service 0xFA not found'));
    BlueZGattCharacteristic ch(String u) => svc.characteristics.firstWhere((c) => c.uuid.toString() == u);
    final link = BlueZLink._(client, dev, ch(IPixelUuids.write), ch(IPixelUuids.notify), ownsClient);
    link._sub = link._notify.propertiesChanged.listen((props) {
      if (props.contains('Value')) link._ctrl.add(Uint8List.fromList(link._notify.value));
    });
    await link._notify.startNotify();
    try {
      final r = await link._write.acquireWrite();
      link._sock = r.socket;
      link._sockMtu = r.mtu;
    } catch (_) {
      // older BlueZ or characteristic without write-without-response: fall back to WriteValue
    }
    return link;
  }

  @override
  Stream<Uint8List> get notifications => _ctrl.stream;

  @override
  int get maxWriteLength => _sock != null ? (_sockMtu - 3).clamp(20, 509).toInt() : (_write.mtu ?? 23) - 3;

  @override
  Future<void> write(Uint8List data, {bool withResponse = true}) async {
    final sock = _sock;
    if (sock == null) {
      return _write.writeValue(data,
          type: withResponse ? BlueZGattCharacteristicWriteType.request : BlueZGattCharacteristicWriteType.command);
    }
    var off = 0;
    while (off < data.length) {
      final n = sock.write(data, off, data.length - off);
      if (n == 0) {
        await Future.delayed(const Duration(milliseconds: 2)); // kernel buffer full, let it drain
      } else {
        off += n;
      }
    }
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sock?.close();
    _sock = null;
    try {
      await _notify.stopNotify();
      await device.disconnect();
    } catch (_) {}
    if (_ownsClient) await client.close();
  }
}
