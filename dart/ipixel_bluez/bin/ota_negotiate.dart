// Non-destructive JieLi OTA negotiation probe. After the E1 auth it:
//   GET_TARGET_INFO (0x03) -> decode version / double-backup / addrs
//   GET_UPDATE_FILE_OFFSET (0xE1) -> which bytes of the .ufw the device validates
//   INQUIRE_UPDATE (0xE2) with that region from a candidate .ufw -> canUpdateFlag
// It STOPS before ENTER_UPDATE_MODE (0xE3) / block send (0xE5) — nothing is written to flash.
//   dart run ipixel_bluez:ota_negotiate <path-to.ufw> [MAC]
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bluez/bluez.dart';
import 'package:ipixel_bluez/jl_auth.dart';

const svcU = '0000ae00-0000-1000-8000-00805f9b34fb';
const wrU = '0000ae01-0000-1000-8000-00805f9b34fb';
const noU = '0000ae02-0000-1000-8000-00805f9b34fb';
String hx(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
int _sn = 1;

List<int> buildCmd(int opcode, [List<int> flagData = const []]) {
  final params = [_sn++ & 0xff, ...flagData];
  final len = params.length;
  return [0xFE, 0xDC, 0xBA, 0xC0, opcode, (len >> 8) & 0xff, len & 0xff, ...params, 0xEF];
}

/// Extract the first complete RCSP frame from [buf]; returns (opcode,status,sn,paramData) or null.
Map<String, dynamic>? parseFrame(List<int> buf) {
  for (var i = 0; i + 8 <= buf.length; i++) {
    if (buf[i] == 0xFE && buf[i + 1] == 0xDC && buf[i + 2] == 0xBA) {
      final len = (buf[i + 5] << 8) | buf[i + 6];
      final end = i + 7 + len; // index of trailer EF
      if (end >= buf.length) return null; // incomplete
      if (buf[end] != 0xEF) continue;
      final op = buf[i + 4];
      final params = buf.sublist(i + 7, end);
      // response (flags bit7==0): [status][sn][paramData]
      final status = params.isNotEmpty ? params[0] : -1;
      final sn = params.length > 1 ? params[1] : -1;
      final data = params.length > 2 ? params.sublist(2) : <int>[];
      return {'op': op, 'status': status, 'sn': sn, 'data': data, 'consumed': end + 1};
    }
  }
  return null;
}

void decodeTargetInfo(List<int> d) {
  var i = 0;
  String mac(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
  while (i + 2 <= d.length) {
    final len = d[i];
    if (len == 0 || len >= d.length) break;
    final type = d[i + 1];
    final v = d.sublist(i + 2, (i + 1 + len).clamp(0, d.length));
    switch (type) {
      case 5:
        if (v.length >= 2) {
          final c = (v[0] << 8) | v[1];
          print('    version: V_${(c >> 12) & 15}.${(c >> 8) & 15}.${(c >> 4) & 15}.${c & 15}  (0x${c.toRadixString(16)})');
        }
      case 8:
        print('    doubleBackup=${v.isNotEmpty && v[0] == 1}  needBootloader=${v.length > 1 && v[1] == 1}'
            '${v.length > 2 ? "  singleBackupWay=${v[2]}" : ""}');
      case 9:
        print('    mandatoryUpgrade=${v.isNotEmpty ? v[0] : "?"}  requestOta=${v.length > 1 ? v[1] : "?"}');
      case 10:
        if (v.length >= 4) print('    vid=${(v[0] << 8) | v[1]} pid=${(v[2] << 8) | v[3]}');
      case 16:
        print('    name="${String.fromCharCodes(v)}"');
      case 17:
        if (v.length >= 7) print('    bleOnly=${v[0] == 1}  bleAddr=${mac(v.sublist(1, 7))}');
    }
    i += len + 1;
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: ota_negotiate <path-to.ufw> [MAC]');
    return;
  }
  final ufwPath = args[0];
  final ufw = File(ufwPath).readAsBytesSync();
  final mac = args.length > 1 ? args[1].toUpperCase() : null;

  final client = BlueZClient();
  await client.connect();
  final adapter = client.adapters.first;
  bool m(BlueZDevice d) => mac != null ? d.address.toUpperCase() == mac : d.name.contains('LED_BLE');
  BlueZDevice? dev;
  for (final d in client.devices) {
    if (m(d)) dev = d;
  }
  if (dev == null) {
    final f = Completer<BlueZDevice>();
    final s = client.deviceAdded.listen((d) {
      if (m(d) && !f.isCompleted) f.complete(d);
    });
    await adapter.startDiscovery();
    dev = await f.future.timeout(const Duration(seconds: 12));
    await s.cancel();
    await adapter.stopDiscovery();
  }
  if (!dev.connected) await dev.connect();
  for (var i = 0; !dev.servicesResolved && i < 120; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  BlueZGattService? svc;
  for (final s in dev.gattServices) {
    if (s.uuid.toString() == svcU) svc = s;
  }
  BlueZGattCharacteristic? wr, no;
  for (final c in svc!.characteristics) {
    if (c.uuid.toString() == wrU) wr = c;
    if (c.uuid.toString() == noU) no = c;
  }

  final buf = <int>[];
  Completer<Map<String, dynamic>>? frameWaiter;
  int? wantOp;
  final rawQueue = <List<int>>[];
  Completer<List<int>>? rawWaiter;
  final sub = no!.propertiesChanged.listen((props) {
    if (!props.contains('Value')) return;
    final v = [...no!.value];
    // auth frames are raw 17/5-byte; RCSP frames start FE DC BA
    if (v.isNotEmpty && v[0] != 0xFE && buf.isEmpty) {
      if (rawWaiter != null) {
        final w = rawWaiter!;
        rawWaiter = null;
        w.complete(v);
      } else {
        rawQueue.add(v);
      }
      return;
    }
    buf.addAll(v);
    final f = parseFrame(buf);
    if (f != null && (wantOp == null || f['op'] == wantOp)) {
      buf.removeRange(0, f['consumed'] as int);
      if (frameWaiter != null) {
        final w = frameWaiter!;
        frameWaiter = null;
        w.complete(f);
      }
    }
  });
  await no.startNotify();

  Future<void> send(List<int> b, String label) async {
    print('-> $label  ${hx(b)}');
    await wr!.writeValue(b, type: BlueZGattCharacteristicWriteType.command);
  }

  Future<List<int>> nextRaw([Duration t = const Duration(seconds: 5)]) {
    if (rawQueue.isNotEmpty) return Future.value(rawQueue.removeAt(0));
    final c = Completer<List<int>>();
    rawWaiter = c;
    return c.future.timeout(t);
  }

  Future<Map<String, dynamic>> cmd(int op, List<int> data, String label, {Duration t = const Duration(seconds: 6)}) async {
    wantOp = op;
    final c = Completer<Map<String, dynamic>>();
    frameWaiter = c;
    await send(buildCmd(op, data), label);
    final r = await c.future.timeout(t);
    print('<- op=0x${(r['op'] as int).toRadixString(16)} status=${r['status']} data=${hx(r['data'] as List<int>)}');
    return r;
  }

  try {
    // ---- auth ----
    final rng = Random();
    final myRand = [for (var i = 0; i < 16; i++) rng.nextInt(256)];
    await send([0x00, ...myRand], 'auth challenge');
    final dr = await nextRaw();
    print('<- ${hx(dr)}');
    await send(jlAuthPass, 'pass');
    final chal = await nextRaw();
    print('<- ${hx(chal)}');
    await send([0x01, ...jlAuthResponse(chal.sublist(1, 17))], 'auth answer');
    final fin = await nextRaw();
    print('<- ${hx(fin)}  ${fin.isNotEmpty && fin[0] == 0x02 ? "AUTHENTICATED" : ""}');

    // ---- target info ----
    print('\n[0x03] GET_TARGET_INFO');
    final ti = await cmd(0x03, [0xFF, 0xFF, 0xFF, 0xFF, 0x00], 'GET_TARGET_INFO');
    decodeTargetInfo(ti['data'] as List<int>);

    // ---- which region does the device validate ----
    print('\n[0xE1] GET_UPDATE_FILE_OFFSET');
    final off = await cmd(0xE1, const [], 'GET_FILE_OFFSET');
    final od = off['data'] as List<int>;
    if (od.length < 6) {
      print('  unexpected offset reply');
    } else {
      final offset = (od[0] << 24) | (od[1] << 16) | (od[2] << 8) | od[3];
      final flen = (od[4] << 8) | od[5];
      print('  device wants update-file-flag: offset=0x${offset.toRadixString(16)} len=$flen (file is ${ufw.length} B)');
      if (offset + flen > ufw.length) {
        print('  !! region is beyond this .ufw — the device expects a different/this-model image');
      } else {
        final region = ufw.sublist(offset, offset + flen);
        print('  region from $ufwPath: ${hx(region)}');
        print('\n[0xE2] INQUIRE_UPDATE (non-destructive accept/reject test)');
        final inq = await cmd(0xE2, region, 'INQUIRE_UPDATE');
        final flag = (inq['data'] as List<int>).isNotEmpty ? (inq['data'] as List<int>)[0] : -1;
        print('  => canUpdateFlag = $flag  (${flag == 0 ? "ACCEPTED/ok" : "rejected/other=$flag"})');
      }
    }
    print('\n[stop] not sending ENTER_UPDATE_MODE / blocks — nothing was written.');
  } on TimeoutException {
    print('timeout waiting for a device frame');
  } finally {
    await sub.cancel();
    try {
      await no.stopNotify();
    } catch (_) {}
    await client.close();
  }
}
