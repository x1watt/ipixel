import 'package:ipixel_fx/ipixel_fx.dart';
import 'package:test/test.dart';

void main() {
  test('pixel font renders known glyph', () {
    // '!' in 5x7 is a vertical bar in column 2: rows 0..3 lit, row 4 gap, row 5 dot, row 6 empty
    final f = PixelFont.small;
    expect(f.pixel(33, 2, 0), isTrue);
    expect(f.pixel(33, 2, 4), isFalse);
    expect(f.pixel(33, 2, 5), isTrue);
    expect(f.pixel(33, 1, 0), isFalse);
    expect(f.textWidth('abc'), 15);
  });

  test('canvas primitives', () {
    final c = PanelCanvas(8, 4);
    c.set(1, 1, 0x123456);
    expect(c.get(1, 1), 0x123456);
    expect(c.rgbBytes.sublist(27, 30), [0x12, 0x34, 0x56]);
    c.set(-1, 0, 0xFFFFFF); // out of bounds ignored
    c.rect(0, 0, 8, 4, 0xFF0000);
    expect(c.get(0, 3), 0xFF0000);
    expect(c.get(3, 1), 0);
  });

  test('every catalog scene draws several frames on 64x16, 32x32 and 16x16 without throwing', () {
    for (final size in [(64, 16), (32, 32), (16, 16), (128, 32)]) {
      for (final e in sceneCatalog) {
        final s = e.create();
        s.init(size.$1, size.$2);
        final c = PanelCanvas(size.$1, size.$2);
        for (var i = 0; i < 30; i++) {
          s.draw(c, i / s.fps, 1 / s.fps);
          for (final inp in SceneInput.values) {
            s.onInput(inp);
          }
        }
      }
    }
  });

  test('hsv and mix', () {
    expect(hsv(0), 0xFF0000);
    expect(hsv(120), 0x00FF00);
    expect(hsv(240), 0x0000FF);
    expect(mix(0x000000, 0xFFFFFF, 0.5), 0x808080);
  });

  test('game auto-players survive 400 frames and score', () {
    for (final e in sceneCatalog.where((e) => e.interactive)) {
      final s = e.create()..init(64, 16);
      s.setParam('auto', true);
      final c = PanelCanvas(64, 16);
      for (var i = 0; i < 400; i++) {
        s.draw(c, i / s.fps, 1 / s.fps);
      }
    }
  });
}
