import 'dart:typed_data';

import 'package:ipixel_protocol/ipixel_protocol.dart';
import 'package:test/test.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
List<int> unhex(String s) => s.split(' ').map((x) => int.parse(x, radix: 16)).toList();

/// Golden values are byte captures from a real 64x16 LED_BLE_3E4F7EB7 (CID 0007 / PID 04).
void main() {
  test('handshake packet', () {
    expect(hex(IPixelCommands.handshake(now: DateTime(2026, 11, 7, 16, 36, 24))),
        '08 00 01 80 10 24 18 00');
  });

  test('handshake reply -> 64x16 panel', () {
    final p = PanelInfo.fromHandshake(unhex('0b 00 01 80 83 24 18 00 00 01 00'));
    expect((p.ledType, p.width, p.height, p.frameSize, p.passwordEnabled), (3, 64, 16, 4096, false));
  });

  test('simple commands', () {
    expect(hex(IPixelCommands.brightness(10)), '05 00 04 80 0a');
    expect(hex(IPixelCommands.power(false)), '05 00 07 01 00');
    expect(hex(IPixelCommands.upsideDown(true)), '05 00 06 80 01');
    expect(hex(IPixelCommands.hwInfo()), '04 00 05 80');
    expect(hex(IPixelCommands.diyMode(DiyMode.enterClear)), '05 00 04 01 01');
    expect(hex(IPixelCommands.clockMode(now: DateTime(2026, 11, 7))), // Saturday -> 6
        '0b 00 06 01 01 01 00 1a 0b 07 06');
  });

  test('diy draw', () {
    expect(hex(IPixelCommands.diyDraw([255, 255, 255], [(63, 0)])), '0a 00 05 01 00 ff ff ff 3f 00');
  });

  test('crc32 matches zlib', () {
    final d = [for (var i = 0; i < 20; i++) ...List.generate(256, (j) => j)];
    expect(crc32(d), 0x670222cb);
  });

  test('live frame packet header', () {
    final p = buildDataPackets(cmd: Cmd.liveFrame, data: Uint8List(64 * 16 * 3), frameSize: 12288, withCrc: false);
    expect(p.length, 1);
    expect(p[0].length, 3081);
    expect(hex(p[0].sublist(0, 9)), '09 0c 00 00 00 00 0c 00 00');
  });

  test('crc data packets split + continuation option', () {
    final data = Uint8List(5000);
    final p = buildDataPackets(cmd: Cmd.gif, data: data, frameSize: 4096, withCrc: true, flag: 2, slot: 101);
    expect(p.length, 2);
    expect(p[0].length, 15 + 4096);
    expect(p[0][4], 0);
    expect(p[1][4], 2);
    expect(p[1].length, 15 + 904);
    expect(hex(p[0].sublist(5, 9)), '88 13 00 00'); // total 5000
    expect(p[0].sublist(9, 13), p[1].sublist(9, 13)); // CRC of whole payload in every frame
    expect(hex(p[0].sublist(13, 15)), '02 65');
  });

  test('1-bit packing is LSB-first with 8px row stride', () {
    final g = Glyph(3, 2, (x, y) => x == 0 || (y == 1 && x == 2));
    expect(hex(pack1bit(g)), '01 05');
  });

  test('advert decode', () {
    final a = IPixelAdvert.fromManufacturerData(unhex('00 72 00 07 04 00 83'))!;
    expect((a.cid, a.pid, a.size), ('0007', '04', 0x83));
    expect(IPixelAdvert.matches(name: 'LED_BLE_3E4F7EB7'), isTrue);
  });

  test('text header', () {
    final t = encodeText('A', color: [0, 200, 255], effect: 1, speed: 50);
    expect(hex(t.sublist(0, 14)), '01 00 01 04 01 32 01 00 c8 ff 00 00 00 00');
    expect(t[14], 0x80);
    expect(t[19], 16); // glyph height
  });

  test('firmware feature commands (from app source)', () {
    expect(hex(IPixelCommands.playlist([3, 1])), '08 00 08 80 02 00 03 01');
    expect(hex(IPixelCommands.countdown(1, 5, 30)), '07 00 0d 80 01 05 1e');
    expect(hex(IPixelCommands.stopwatch(2)), '05 00 09 80 02');
    expect(hex(IPixelCommands.scoreboard(300, 7)), '08 00 0a 80 2c 01 07 00');
    expect(hex(IPixelCommands.sport(6, speed: 23, tenths: 4)), '07 00 06 00 06 17 04');
    expect(IPixelCommands.weekMask([true, false, false, false, false, false, true]), 0x83);
    expect(hex(IPixelCommands.schedule(index: 0, on: true, hour: 7, minute: 30, days: List.filled(7, true))),
        '09 00 11 80 01 00 ff 07 1e');
    expect(hex(IPixelCommands.setPassword(true, [12, 34, 56])), '08 00 04 02 01 0c 22 38');
    expect(hex(IPixelCommands.verifyPassword([12, 34])), '07 00 05 02 0c 22 00');
    expect(hex(IPixelCommands.rhythmChart(2, [15, 3])), '10 00 01 02 02 0f 03 00 00 00 00 00 00 00 00 00');
  });
}
