import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Colours are plain ints 0xRRGGBB.
int rgb(int r, int g, int b) => (r.clamp(0, 255) << 16) | (g.clamp(0, 255) << 8) | b.clamp(0, 255);

/// HSV (h in degrees, s/v 0..1) -> 0xRRGGBB.
int hsv(double h, [double s = 1, double v = 1]) {
  h = h % 360;
  final c = v * s, x = c * (1 - ((h / 60) % 2 - 1).abs()), m = v - c;
  final (r, g, b) = h < 60
      ? (c, x, 0.0)
      : h < 120
          ? (x, c, 0.0)
          : h < 180
              ? (0.0, c, x)
              : h < 240
                  ? (0.0, x, c)
                  : h < 300
                      ? (x, 0.0, c)
                      : (c, 0.0, x);
  return rgb(((r + m) * 255).round(), ((g + m) * 255).round(), ((b + m) * 255).round());
}

/// Linear blend of two colours, t in 0..1.
int mix(int a, int b, double t) {
  t = t.clamp(0, 1);
  int ch(int s) => (((a >> s) & 255) * (1 - t) + ((b >> s) & 255) * t).round();
  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// Scale brightness, f in 0..1+.
int dim(int c, double f) => rgb(((c >> 16 & 255) * f).round(), ((c >> 8 & 255) * f).round(), ((c & 255) * f).round());

/// RGB888 frame buffer the size of the panel.
class PanelCanvas {
  final int width, height;
  final Uint8List rgbBytes;
  PanelCanvas(this.width, this.height) : rgbBytes = Uint8List(width * height * 3);

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  void clear([int c = 0]) {
    if (c == 0) {
      rgbBytes.fillRange(0, rgbBytes.length, 0);
      return;
    }
    for (var i = 0; i < width * height; i++) {
      rgbBytes[i * 3] = c >> 16 & 255;
      rgbBytes[i * 3 + 1] = c >> 8 & 255;
      rgbBytes[i * 3 + 2] = c & 255;
    }
  }

  void set(int x, int y, int c) {
    if (!inside(x, y)) return;
    final i = (y * width + x) * 3;
    rgbBytes[i] = c >> 16 & 255;
    rgbBytes[i + 1] = c >> 8 & 255;
    rgbBytes[i + 2] = c & 255;
  }

  int get(int x, int y) {
    if (!inside(x, y)) return 0;
    final i = (y * width + x) * 3;
    return rgbBytes[i] << 16 | rgbBytes[i + 1] << 8 | rgbBytes[i + 2];
  }

  /// Additive set (light adds up, clamps at white).
  void add(int x, int y, int c) {
    if (!inside(x, y)) return;
    final o = get(x, y);
    set(x, y, rgb((o >> 16 & 255) + (c >> 16 & 255), (o >> 8 & 255) + (c >> 8 & 255), (o & 255) + (c & 255)));
  }

  void fillRect(int x, int y, int w, int h, int c) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        set(xx, yy, c);
      }
    }
  }

  void rect(int x, int y, int w, int h, int c) {
    for (var i = 0; i < w; i++) {
      set(x + i, y, c);
      set(x + i, y + h - 1, c);
    }
    for (var i = 0; i < h; i++) {
      set(x, y + i, c);
      set(x + w - 1, y + i, c);
    }
  }

  void line(int x0, int y0, int x1, int y1, int c) {
    final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      set(x0, y0, c);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  void circle(int cx, int cy, int r, int c, {bool fill = false}) {
    for (var y = -r; y <= r; y++) {
      for (var x = -r; x <= r; x++) {
        final d = x * x + y * y;
        if (fill ? d <= r * r + r : (d >= r * r - r && d <= r * r + r)) set(cx + x, cy + y, c);
      }
    }
  }

  /// Fade every pixel towards black (trails).
  void fade(double f) {
    for (var i = 0; i < rgbBytes.length; i++) {
      rgbBytes[i] = (rgbBytes[i] * f).floor();
    }
  }

  /// Draw an image (any size) scaled to fit [w]x[h] at x,y.
  void drawImage(img.Image src, {int x = 0, int y = 0, int? w, int? h}) {
    final tw = w ?? width, th = h ?? height;
    final s = img.copyResize(src, width: tw, height: th, interpolation: img.Interpolation.average);
    for (var yy = 0; yy < th; yy++) {
      for (var xx = 0; xx < tw; xx++) {
        final p = s.getPixel(xx, yy);
        if (p.a < 128) continue;
        set(x + xx, y + yy, rgb(p.r.toInt(), p.g.toInt(), p.b.toInt()));
      }
    }
  }

  /// Copy of the bytes (safe to send while the canvas keeps changing).
  Uint8List snapshot() => Uint8List.fromList(rgbBytes);

  /// Upscaled image for previews / PNG export.
  img.Image toImage({int scale = 1}) {
    final im = img.Image(width: width * scale, height: height * scale);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = get(x, y);
        for (var sy = 0; sy < scale; sy++) {
          for (var sx = 0; sx < scale; sx++) {
            im.setPixelRgb(x * scale + sx, y * scale + sy, c >> 16 & 255, c >> 8 & 255, c & 255);
          }
        }
      }
    }
    return im;
  }
}

final rng = math.Random();
