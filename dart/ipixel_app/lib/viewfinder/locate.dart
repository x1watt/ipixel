import 'dart:typed_data';

/// Colour of the viewfinder frame. Pure magenta is rare in normal UIs.
const markerR = 255, markerG = 0, markerB = 255;

bool _isMarker(Uint8List p, int i) => p[i] > 200 && p[i + 1] < 70 && p[i + 2] > 200;

/// Interior of the viewfinder frame, in captured-frame pixels.
class Hole {
  final int x, y, w, h;
  const Hole(this.x, this.y, this.w, this.h);
  @override
  String toString() => '${w}x$h at $x,$y';
}

/// Finds the magenta frame in a captured RGB frame and returns its exact interior, or null.
Hole? locateViewfinder(Uint8List rgb, int w, int h) {
  var minX = w, minY = h, maxX = -1, maxY = -1, count = 0;
  for (var y = 0; y < h; y++) {
    var i = y * w * 3;
    for (var x = 0; x < w; x++, i += 3) {
      if (_isMarker(rgb, i)) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        count++;
      }
    }
  }
  if (count < 40 || maxX - minX < 8 || maxY - minY < 4) return null;
  // frame thickness along the middle row / middle column
  int run(int x, int y, int dx, int dy) {
    var n = 0;
    while (x >= 0 && y >= 0 && x < w && y < h && _isMarker(rgb, (y * w + x) * 3)) {
      x += dx;
      y += dy;
      n++;
    }
    return n;
  }
  final my = (minY + maxY) ~/ 2, mx = (minX + maxX) ~/ 2;
  final tl = run(minX, my, 1, 0), tr = run(maxX, my, -1, 0);
  final tt = run(mx, minY, 0, 1), tb = run(mx, maxY, 0, -1);
  final hw = maxX - minX + 1 - tl - tr, hh = maxY - minY + 1 - tt - tb;
  if (hw < 2 || hh < 2) return null;
  return _trimPinkEdges(rgb, w, Hole(minX + tl, minY + tt, hw, hh));
}

/// Blended frame edges (fractional window positions) are pinkish but not pure magenta:
/// shave any interior edge row/column where most pixels look pinkish.
bool _pinkish(Uint8List p, int i) => p[i] - p[i + 1] > 60 && p[i + 2] - p[i + 1] > 60;

Hole _trimPinkEdges(Uint8List rgb, int w, Hole h) {
  var x = h.x, y = h.y, x2 = h.x + h.w - 1, y2 = h.y + h.h - 1;
  bool rowPink(int yy) {
    var n = 0;
    for (var xx = x; xx <= x2; xx++) {
      if (_pinkish(rgb, (yy * w + xx) * 3)) n++;
    }
    return n * 2 > (x2 - x + 1);
  }
  bool colPink(int xx) {
    var n = 0;
    for (var yy = y; yy <= y2; yy++) {
      if (_pinkish(rgb, (yy * w + xx) * 3)) n++;
    }
    return n * 2 > (y2 - y + 1);
  }
  for (var k = 0; k < 3 && y < y2 && rowPink(y); k++) {
    y++;
  }
  for (var k = 0; k < 3 && y2 > y && rowPink(y2); k++) {
    y2--;
  }
  for (var k = 0; k < 3 && x < x2 && colPink(x); k++) {
    x++;
  }
  for (var k = 0; k < 3 && x2 > x && colPink(x2); k++) {
    x2--;
  }
  return Hole(x, y, x2 - x + 1, y2 - y + 1);
}

/// 1:1 crop with integer [zoom] (each output pixel = mean of a zoom x zoom block),
/// centred in the hole. Falls back to [cropHole] scaling if the hole is too small.
Uint8List cropExact(Uint8List src, int srcW, Hole hole, int outW, int outH, {int zoom = 1}) {
  final needW = outW * zoom, needH = outH * zoom;
  if (hole.w < needW || hole.h < needH) return cropHole(src, srcW, hole, outW, outH);
  final x0 = hole.x + (hole.w - needW) ~/ 2, y0 = hole.y + (hole.h - needH) ~/ 2;
  return cropHole(src, srcW, Hole(x0, y0, needW, needH), outW, outH);
}

/// Box-filter the [hole] of an RGB frame down to outW x outH RGB.
Uint8List cropHole(Uint8List src, int srcW, Hole hole, int outW, int outH) {
  final out = Uint8List(outW * outH * 3);
  final sx = hole.w / outW, sy = hole.h / outH;
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final ya = hole.y + (oy * sy).floor(), yb = hole.y + ((oy + 1) * sy).ceil();
    for (var ox = 0; ox < outW; ox++) {
      final xa = hole.x + (ox * sx).floor(), xb = hole.x + ((ox + 1) * sx).ceil();
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = ya; y < yb; y++) {
        var i = (y * srcW + xa) * 3;
        for (var x = xa; x < xb; x++, i += 3) {
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          n++;
        }
      }
      out[o++] = r ~/ n;
      out[o++] = g ~/ n;
      out[o++] = b ~/ n;
    }
  }
  return out;
}
