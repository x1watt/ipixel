import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'codec.dart';

/// One rendered character: 1 bit per pixel, row-major.
class Glyph {
  final int width, height;
  final bool Function(int x, int y) pixel;
  const Glyph(this.width, this.height, this.pixel);
}

/// Renders a character to a [Glyph]. Supply your own (e.g. Flutter TextPainter)
/// for nicer fonts / non-Latin scripts; [bitmapFontGlyph] is a pure-Dart default.
typedef GlyphRenderer = Glyph Function(String ch, int height);

/// Text animation (header byte 4), in the official app's picker order.
/// 0, 1 verified on hardware. Up/down are for vertical text on tall panels.
class TextEffect {
  static const fixed = 0;
  static const scrollLeft = 1;
  static const scrollRight = 2;
  static const scrollUp = 3;
  static const scrollDown = 4;
  static const blink = 5;
  static const breathe = 6;
  static const snowflakes = 7;
  static const laser = 8;
  static const names = ['Static', 'Scroll left', 'Scroll right', 'Scroll up', 'Scroll down', 'Blink', 'Breathe', 'Snow', 'Laser'];
}

/// Horizontal alignment (header byte 2) for text that fits.
class TextAlign {
  static const left = 0, center = 1, right = 2;
}

/// Vertical alignment (header byte 3): the firmware counts from 3.
class TextVAlign {
  static const top = 3, middle = 4, bottom = 5;
}

/// Colour mode (header byte 6): 1 = solid RGB; 2..9 = firmware gradient/texture presets
/// (the RGB bytes are then ignored). 0 is what the app sends for pure white.
class TextColorMode {
  static const solid = 1;
  static int gradient(int preset) => 2 + preset.clamp(0, 7);
}

/// Pack a glyph the way TextAgreement.getTextData does: rows padded to a multiple
/// of 8 px, bit i of each byte = pixel (8*byteIndex + i) -> LSB is the leftmost pixel.
Uint8List pack1bit(Glyph g) {
  final stride = (g.width + 7) ~/ 8 * 8;
  final out = Uint8List(stride * g.height ~/ 8);
  for (var y = 0; y < g.height; y++) {
    for (var x = 0; x < g.width; x++) {
      if (g.pixel(x, y)) {
        final i = y * stride + x;
        out[i >> 3] |= 1 << (i & 7);
      }
    }
  }
  return out;
}

/// Pure-Dart renderer using the `image` package bitmap fonts (arial 14/24/48).
Glyph bitmapFontGlyph(String ch, int height) {
  final font = height >= 48 ? img.arial48 : (height >= 24 ? img.arial24 : img.arial14);
  final c = font.characters[ch.codeUnitAt(0)];
  final w = (c?.xAdvance ?? height ~/ 3).clamp(1, 255);
  final canvas = img.Image(width: w, height: height);
  final y = ((height - font.lineHeight) / 2).round();
  img.drawString(canvas, ch, font: font, x: 0, y: y, color: img.ColorRgb8(255, 255, 255));
  return Glyph(w, height, (x, y) => canvas.getPixel(x, y).luminance > 64);
}

/// Encode a text program (cmd 0x0100 payload).
///
/// Header (14 B): `[u16 count][h-align][v-align][effect][speed][colorMode][R G B][bgOn][bgR bgG bgB]`
/// Per char: `[0x80][R G B][w][h][1-bit bitmap]`.
/// Panels with ledType 16..19 or >= 24 add 3 border bytes: [type][speed][effect].
Uint8List encodeText(
  String text, {
  List<int> color = const [255, 255, 255],
  List<int>? background,
  int effect = TextEffect.scrollLeft,
  int speed = 50,
  int height = 16,
  int hAlign = TextAlign.center,
  int vAlign = TextVAlign.middle,
  int colorMode = TextColorMode.solid,
  GlyphRenderer renderer = bitmapFontGlyph,
  int? ledType,
  List<int> border = const [0, 0, 0],
}) {
  final chars = text.replaceAll('\n', ' ').runes.map(String.fromCharCode).toList();
  final out = BytesBuilder()
    ..add([
      ...u16le(chars.length), hAlign, vAlign, effect, speed, colorMode, ...color,
      background == null ? 0 : 1, ...(background ?? const [0, 0, 0]),
    ]);
  if (ledType != null && ((ledType >= 16 && ledType < 20) || ledType >= 24)) out.add(border);
  for (final ch in chars) {
    final g = renderer(ch, height);
    out
      ..add([0x80, ...color, g.width, g.height])
      ..add(pack1bit(g));
  }
  return out.toBytes();
}
