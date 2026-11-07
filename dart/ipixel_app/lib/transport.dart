import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';
import 'package:ipixel_bluez/ipixel_bluez.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'fbp_link.dart';

/// A display found while scanning, independent of the BLE stack.
class FoundDisplay {
  final String id, name;
  final int rssi;
  final IPixelAdvert? advert;
  final Object raw;
  const FoundDisplay(this.id, this.name, this.rssi, this.advert, this.raw);
}

/// Scanning + connecting, one implementation per BLE stack.
abstract class DisplayFinder {
  /// Linux uses BlueZ directly (pure Dart); everything else uses flutter_blue_plus.
  factory DisplayFinder() => Platform.isLinux ? _BlueZFinder() : _FbpFinder();

  /// null = unknown/not applicable, false = Bluetooth off.
  Stream<bool?> get adapterOn;
  Stream<List<FoundDisplay>> scan();
  Future<void> stopScan();
  Future<BleLink> connect(FoundDisplay d);
  Future<void> turnOn() async {}
  Future<void> dispose();
}

class _FbpFinder implements DisplayFinder {
  @override
  Stream<bool?> get adapterOn => FlutterBluePlus.adapterState.map((s) => switch (s) {
        BluetoothAdapterState.on => true,
        BluetoothAdapterState.unknown || BluetoothAdapterState.turningOn => null,
        _ => false,
      });

  @override
  Stream<List<FoundDisplay>> scan() => FbpLink.scan().map((rs) => [
        for (final r in rs)
          FoundDisplay(
            r.device.remoteId.str,
            r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName,
            r.rssi,
            switch (r.advertisementData.manufacturerData[ipixelManufacturerIdLE]) {
              final m? => IPixelAdvert.fromManufacturerData(m),
              null => null,
            },
            r.device,
          ),
      ]);

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<BleLink> connect(FoundDisplay d) async {
    await stopScan();
    return FbpLink.connect(d.raw as BluetoothDevice);
  }

  @override
  Future<void> turnOn() => FlutterBluePlus.turnOn();

  @override
  Future<void> dispose() => stopScan();
}

class _BlueZFinder implements DisplayFinder {
  BlueZScanner? _scanner;

  @override
  Stream<bool?> get adapterOn => Stream.value(true);

  @override
  Stream<List<FoundDisplay>> scan() async* {
    await _scanner?.close();
    final s = _scanner = BlueZScanner();
    await s.start();
    yield _map(s.current);
    yield* s.results.map(_map);
  }

  List<FoundDisplay> _map(List<BlueZDisplay> l) =>
      [for (final d in l) FoundDisplay(d.address, d.name, d.rssi, d.advert, d)];

  @override
  Future<void> stopScan() async => _scanner?.stopDiscovery();

  @override
  Future<BleLink> connect(FoundDisplay d) => _scanner!.connect(d.raw as BlueZDisplay);

  @override
  Future<void> turnOn() async {}

  @override
  Future<void> dispose() async => _scanner?.close();
}
