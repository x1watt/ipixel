// JieLi RCSP OTA: authenticate (E1 handshake) then read device info. NON-DESTRUCTIVE —
// it performs the auth and sends GET_TARGET_INFO only; it never enters update mode or writes.
//   dart run ipixel_bluez:ota_auth_probe selftest   # validate E1 against vectors
//   dart run ipixel_bluez:ota_auth_probe [MAC]       # auth + GET_TARGET_INFO on the panel
import 'dart:async';
import 'dart:math';

import 'package:bluez/bluez.dart';
import 'package:ipixel_bluez/jl_auth.dart';

const otaService = '0000ae00-0000-1000-8000-00805f9b34fb';
const otaWrite = '0000ae01-0000-1000-8000-00805f9b34fb';
const otaNotify = '0000ae02-0000-1000-8000-00805f9b34fb';
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == 'selftest') {
    print('E1 self-test: ${e1SelfTest() ? "PASS" : "FAIL"}');
    return;
  }
  final mac = args.isNotEmpty ? args[0].toUpperCase() : null;
  final client = BlueZClient();
  await client.connect();
  final adapter = client.adapters.first;
  bool match(BlueZDevice d) => mac != null ? d.address.toUpperCase() == mac : d.name.contains('LED_BLE');

  BlueZDevice? dev;
  for (final d in client.devices) {
    if (match(d)) dev = d;
  }
  if (dev == null) {
    final found = Completer<BlueZDevice>();
    final s = client.deviceAdded.listen((d) {
      if (match(d) && !found.isCompleted) found.complete(d);
    });
    await adapter.startDiscovery();
    dev = await found.future.timeout(const Duration(seconds: 12));
    await s.cancel();
    await adapter.stopDiscovery();
  }
  print('device ${dev.address} "${dev.name}" connected=${dev.connected}');
  if (!dev.connected) await dev.connect();
  for (var i = 0; !dev.servicesResolved && i < 120; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  BlueZGattService? svc;
  for (final s in dev.gattServices) {
    if (s.uuid.toString() == otaService) svc = s;
  }
  if (svc == null) {
    print('OTA service 0xAE00 not found');
    await client.close();
    return;
  }
  BlueZGattCharacteristic? wr, no;
  for (final c in svc.characteristics) {
    if (c.uuid.toString() == otaWrite) wr = c;
    if (c.uuid.toString() == otaNotify) no = c;
  }

  // incoming-notification queue
  final queue = <List<int>>[];
  Completer<List<int>>? waiter;
  final sub = no!.propertiesChanged.listen((props) {
    if (props.contains('Value')) {
      final v = [...no!.value];
      print('<- ${hex(v)}');
      if (waiter != null) {
        final w = waiter!;
        waiter = null;
        w.complete(v);
      } else {
        queue.add(v);
      }
    }
  });
  await no.startNotify();

  Future<List<int>> next([Duration t = const Duration(seconds: 5)]) {
    if (queue.isNotEmpty) return Future.value(queue.removeAt(0));
    final c = Completer<List<int>>();
    waiter = c;
    return c.future.timeout(t);
  }

  Future<void> send(List<int> b) async {
    print('-> ${hex(b)}');
    await wr!.writeValue(b, type: BlueZGattCharacteristicWriteType.command);
  }

  try {
    // ---- E1 handshake ----
    final rng = Random();
    final myRand = [for (var i = 0; i < 16; i++) rng.nextInt(256)];
    print('\n[auth] step 1: host challenge');
    await send([0x00, ...myRand]);

    final devResp = await next();
    final want = jlAuthResponse(myRand);
    final okDev = devResp.length >= 17 && devResp[0] == 0x01 &&
        List.generate(16, (i) => devResp[1 + i]).toString() == want.toString();
    print('[auth] device response ${okDev ? "VERIFIED (knows the key)" : "mismatch/unexpected"}');
    print('[auth] step 2: send pass');
    await send(jlAuthPass);

    final devChal = await next();
    if (devChal.isEmpty || devChal[0] != 0x00 || devChal.length < 17) {
      print('[auth] expected device challenge (00 ..), got ${hex(devChal)} — aborting');
    } else {
      final chal = devChal.sublist(1, 17);
      print('[auth] step 3: answer device challenge');
      await send([0x01, ...jlAuthResponse(chal)]);
      final fin = await next();
      final authed = fin.length >= 5 && fin[0] == 0x02;
      print('[auth] ${authed ? "AUTHENTICATED ✓" : "final frame ${hex(fin)}"}');
    }

    // ---- non-destructive GET_TARGET_INFO ----
    print('\n[rcsp] GET_TARGET_INFO');
    await send([0xFE, 0xDC, 0xBA, 0xC0, 0x03, 0x00, 0x06, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xEF]);
    try {
      final r = await next(const Duration(seconds: 5));
      print('[rcsp] target-info reply: ${hex(r)}');
    } on TimeoutException {
      print('[rcsp] no target-info reply within 5s');
    }
  } on TimeoutException {
    print('timed out waiting for a device frame');
  } finally {
    await sub.cancel();
    try {
      await no.stopNotify();
    } catch (_) {}
    await client.close();
  }
}
