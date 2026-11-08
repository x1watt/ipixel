// Connect to the panel and print every GATT service + characteristic it exposes.
// Used to check for the JieLi OTA service 0xAE00 (write AE01, notify AE02).
//   dart run ipixel_bluez:gatt_discover [MAC]
import 'dart:async';

import 'package:bluez/bluez.dart';

Future<void> main(List<String> args) async {
  final mac = args.isNotEmpty ? args[0].toUpperCase() : null;
  final client = BlueZClient();
  await client.connect();
  if (client.adapters.isEmpty) {
    print('no Bluetooth adapter');
    await client.close();
    return;
  }
  final adapter = client.adapters.first;

  bool match(BlueZDevice d) =>
      mac != null ? d.address.toUpperCase() == mac : d.name.contains('LED_BLE');

  BlueZDevice? dev;
  for (final d in client.devices) {
    if (match(d)) {
      dev = d;
      break;
    }
  }
  if (dev == null) {
    final found = Completer<BlueZDevice>();
    final s = client.deviceAdded.listen((d) {
      if (match(d) && !found.isCompleted) found.complete(d);
    });
    await adapter.startDiscovery();
    try {
      dev = await found.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      print('device not found (scanning ${mac ?? "LED_BLE*"})');
      await s.cancel();
      await adapter.stopDiscovery();
      await client.close();
      return;
    }
    await s.cancel();
    await adapter.stopDiscovery();
  }

  print('device ${dev.address}  "${dev.name}"  connected=${dev.connected}');
  if (!dev.connected) await dev.connect();
  for (var i = 0; !dev.servicesResolved && i < 120; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  print('servicesResolved=${dev.servicesResolved}  (${dev.gattServices.length} services)\n');
  for (final svc in dev.gattServices) {
    print('service ${svc.uuid}');
    for (final ch in svc.characteristics) {
      final flags = ch.flags.map((f) => f.toString().split('.').last).join(',');
      print('    char ${ch.uuid}  [$flags]');
    }
  }
  final hasOta = dev.gattServices.any((s) => s.uuid.toString().toLowerCase().contains('ae00'));
  print('\nJieLi OTA service 0xAE00 present: $hasOta');
  await client.close();
}
