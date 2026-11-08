// Non-destructive JieLi RCSP OTA probe: connect to the panel's 0xAE00 service and
// send GET_TARGET_INFO (opcode 0x03), printing whatever the device replies on AE02.
// This ONLY reads device/firmware info — it never enters update mode or writes flash.
//   dart run ipixel_bluez:ota_probe [MAC]
import 'dart:async';

import 'package:bluez/bluez.dart';

const otaService = '0000ae00-0000-1000-8000-00805f9b34fb';
const otaWrite = '0000ae01-0000-1000-8000-00805f9b34fb';
const otaNotify = '0000ae02-0000-1000-8000-00805f9b34fb';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

Future<void> main(List<String> args) async {
  final mac = args.isNotEmpty ? args[0].toUpperCase() : null;
  final client = BlueZClient();
  await client.connect();
  final adapter = client.adapters.first;
  bool match(BlueZDevice d) =>
      mac != null ? d.address.toUpperCase() == mac : d.name.contains('LED_BLE');

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
  if (wr == null || no == null) {
    print('OTA characteristics missing (write=$wr notify=$no)');
    await client.close();
    return;
  }

  final replies = <List<int>>[];
  final sub = no.propertiesChanged.listen((props) {
    if (props.contains('Value')) {
      replies.add([...no!.value]);
      print('<- ${hex(no.value)}');
    }
  });
  await no.startNotify();

  // GET_TARGET_INFO (0x03), "get all" mask=0xFFFFFFFF, platform=0, sn=1.
  const sn = 0x01;
  final frame = [0xFE, 0xDC, 0xBA, 0xC0, 0x03, 0x00, 0x06, sn, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xEF];
  print('-> ${hex(frame)}  (GET_TARGET_INFO)');
  await wr.writeValue(frame, type: BlueZGattCharacteristicWriteType.command);

  await Future.delayed(const Duration(seconds: 4));
  await sub.cancel();
  try {
    await no.stopNotify();
  } catch (_) {}
  print('\nreplies: ${replies.length}');
  if (replies.isEmpty) {
    print('No response. Either the device requires RcspAuth first, or the flag/frame needs adjusting.');
  } else {
    final r = replies.expand((e) => e).toList();
    print('raw: ${hex(r)}');
    // Expected: FE DC BA <flags> 03 <lenHi> <lenLo> <status> <sn> <targetinfo...> EF
    final i = _find(r, [0xFE, 0xDC, 0xBA]);
    if (i >= 0 && r.length >= i + 7) {
      final op = r[i + 4];
      final len = (r[i + 5] << 8) | r[i + 6];
      final status = r.length > i + 7 ? r[i + 7] : -1;
      print('parsed: opcode=0x${op.toRadixString(16)} paramLen=$len status=$status');
    }
  }
  await client.close();
}

int _find(List<int> h, List<int> n) {
  for (var i = 0; i + n.length <= h.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
