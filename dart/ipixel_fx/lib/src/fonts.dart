import 'canvas.dart';

part 'fonts_data.dart';

/// Monospaced bitmap font (ASCII 32..126) from the public-domain X11 misc-fixed set.
class PixelFont {
  final int w, h;
  final List<int> _data;
  const PixelFont._(this.w, this.h, this._data);

  static const tiny = PixelFont._(_tinyW, _tinyH, _tinyData); // 4x6
  static const small = PixelFont._(_smallW, _smallH, _smallData); // 5x7
  static const medium = PixelFont._(_mediumW, _mediumH, _mediumData); // 6x10
  static const large = PixelFont._(_largeW, _largeH, _largeData); // 6x13

  /// Largest font whose height (times [scale]) fits [px].
  static PixelFont fitting(int px) => px >= 13
      ? large
      : px >= 10
          ? medium
          : px >= 7
              ? small
              : tiny;

  bool pixel(int code, int x, int y) {
    if (code < 32 || code > 126) code = 63; // '?'
    return (_data[(code - 32) * h + y] >> (w - 1 - x)) & 1 == 1;
  }

  int textWidth(String s, {int scale = 1, int spacing = 0}) =>
      s.isEmpty ? 0 : (s.length * (w + spacing) - spacing) * scale;

  /// Draw [s] with its top-left at x,y. [shadow] draws a dark copy 1px down-right.
  void draw(PanelCanvas c, String s, int x, int y, int color, {int scale = 1, int spacing = 0, int? shadow}) {
    if (shadow != null) draw(c, s, x + 1, y + 1, shadow, scale: scale, spacing: spacing);
    var cx = x;
    for (final code in s.codeUnits) {
      if (cx > c.width) break;
      if (cx + w * scale >= 0) {
        for (var gy = 0; gy < h; gy++) {
          for (var gx = 0; gx < w; gx++) {
            if (pixel(code, gx, gy)) {
              if (scale == 1) {
                c.set(cx + gx, y + gy, color);
              } else {
                c.fillRect(cx + gx * scale, y + gy * scale, scale, scale, color);
              }
            }
          }
        }
      }
      cx += (w + spacing) * scale;
    }
  }

  /// Draw centred horizontally (and vertically if [y] is null).
  void drawCentered(PanelCanvas c, String s, int color, {int? y, int scale = 1, int spacing = 0, int? shadow}) {
    final tw = textWidth(s, scale: scale, spacing: spacing);
    draw(c, s, ((c.width - tw) / 2).floor(), y ?? ((c.height - h * scale) / 2).floor(), color,
        scale: scale, spacing: spacing, shadow: shadow);
  }
}

/// Horizontally scrolling text helper (marquee).
class Marquee {
  String text;
  final PixelFont font;
  final double pxPerSec;
  final int gap;
  /// Current scroll offset in pixels (exposed so scenes can swap fonts without a jump).
  double offset = 0;
  Marquee(this.text, {this.font = PixelFont.small, this.pxPerSec = 20, this.gap = 16});

  /// Draw at row [y]; if the text fits in [width] it is centred instead of scrolling.
  void draw(PanelCanvas c, int y, int color, double dt, {int x = 0, int? width, int? shadow}) {
    final w = width ?? c.width;
    final tw = font.textWidth(text);
    if (tw <= w) {
      font.draw(c, text, x + (w - tw) ~/ 2, y, color, shadow: shadow);
      return;
    }
    offset = (offset + pxPerSec * dt) % (tw + gap);
    final sx = x - offset.floor();
    font.draw(c, text, sx, y, color, shadow: shadow);
    font.draw(c, text, sx + tw + gap, y, color, shadow: shadow);
  }
}
