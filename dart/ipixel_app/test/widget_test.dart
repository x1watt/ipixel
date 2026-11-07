import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipixel_app/viewfinder/locate.dart';
import 'package:ipixel_app/pages/text_page.dart';
import 'package:ipixel_app/session.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

/// Fake panel: acks every frame like the real 64x16 display.
class FakeLink implements BleLink {
  final _ctrl = StreamController<Uint8List>.broadcast();
  final writes = <Uint8List>[];
  int _need = 0;
  final _buf = <int>[];
  @override
  Stream<Uint8List> get notifications => _ctrl.stream;
  @override
  int get maxWriteLength => 509;
  @override
  Future<void> write(Uint8List data, {bool withResponse = true}) async {
    writes.add(data);
    _buf.addAll(data);
    if (_need == 0 && _buf.length >= 2) _need = _buf[0] | _buf[1] << 8;
    if (_need > 0 && _buf.length >= _need) {
      final cmd = _buf[2] | _buf[3] << 8;
      _buf.clear();
      _need = 0;
      scheduleMicrotask(() => _ctrl.add(cmd == 0x8001
          ? Uint8List.fromList([0x0b, 0, 1, 0x80, 0x83, 0, 0, 0, 0, 1, 0])
          : Uint8List.fromList([5, 0, cmd & 0xff, cmd >> 8, cmd == 0x0100 ? 3 : 1])));
    }
  }
  @override
  Future<void> disconnect() async {}
}

void main() {
  testWidgets('text page sends text and reports done', (tester) async {
    final link = FakeLink();
    late Session session;
    await tester.runAsync(() async {
      final dev = IPixelDevice(link);
      await dev.handshake();
      session = Session(dev, 'test');
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextPage(session: session))));
    await tester.enterText(find.byType(TextField), 'Hi there');
    await tester.tap(find.text('Send'));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100)); // let the page's own timers (player stop delay) fire
    }
    final status = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>()
        .firstWhere((s) => s.startsWith('Text:') || s.startsWith('Text…') || s.startsWith('Text failed'), orElse: () => '<none>');
    debugPrint('STATUS: $status');
    expect(status, contains('done'));
  });

  test('viewfinder frame is located and its interior cropped', () {
    const w = 400, h = 300;
    final rgb = Uint8List(w * h * 3);
    // gray desktop, magenta frame (4 px) around a 128x32 hole at (100,80) filled red/blue halves
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        final inFrame = x >= 96 && x < 232 && y >= 76 && y < 116;
        final inHole = x >= 100 && x < 228 && y >= 80 && y < 112;
        final c = inHole ? (x < 164 ? [255, 0, 0] : [0, 0, 255]) : inFrame ? [255, 0, 255] : [90, 90, 90];
        rgb.setAll(i, c);
      }
    }
    // blended pinkish edge row inside the frame (fractional positioning) must be trimmed
    for (var x = 100; x < 228; x++) {
      rgb.setAll((80 * w + x) * 3, [200, 60, 190]);
    }
    final hole = locateViewfinder(rgb, w, h)!;
    expect((hole.x, hole.y, hole.w, hole.h), (100, 81, 128, 31)); // pinkish row shaved
    final out = cropExact(rgb, w, hole, 64, 16, zoom: 2);
    expect(out.sublist(0, 3), [255, 0, 0]); // left = red
    expect(out.sublist(63 * 3, 64 * 3), [0, 0, 255]); // right = blue
    expect(locateViewfinder(Uint8List(w * h * 3), w, h), isNull);
  });
}
