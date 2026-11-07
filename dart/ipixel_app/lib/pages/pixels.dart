import 'dart:typed_data';

/// RGB888 -> RGBA8888 (for ui.decodeImageFromPixels).
Uint8List rgbToRgba(Uint8List rgb, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0, o = 0; i < w * h * 3; i += 3, o += 4) {
    out[o] = rgb[i];
    out[o + 1] = rgb[i + 1];
    out[o + 2] = rgb[i + 2];
    out[o + 3] = 255;
  }
  return out;
}

/// RGBA8888 (srcW x srcH) -> RGB888 at exactly outW x outH, box-filtered.
/// Transparent pixels become black (unlit LEDs).
Uint8List rgbaToPanelRgb(ByteData src, int srcW, int srcH, int outW, int outH) {
  final out = Uint8List(outW * outH * 3);
  final sx = srcW / outW, sy = srcH / outH;
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final ya = (oy * sy).floor(), yb = ((oy + 1) * sy).ceil().clamp(ya + 1, srcH);
    for (var ox = 0; ox < outW; ox++) {
      final xa = (ox * sx).floor(), xb = ((ox + 1) * sx).ceil().clamp(xa + 1, srcW);
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = ya; y < yb; y++) {
        for (var x = xa; x < xb; x++) {
          final i = (y * srcW + x) * 4;
          final a = src.getUint8(i + 3);
          r += src.getUint8(i) * a ~/ 255;
          g += src.getUint8(i + 1) * a ~/ 255;
          b += src.getUint8(i + 2) * a ~/ 255;
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
