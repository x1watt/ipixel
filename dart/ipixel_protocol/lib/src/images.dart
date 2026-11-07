import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// RGB888 row-major bytes for a live frame (cmd 0x0000). Must be exactly w*h*3 bytes.
Uint8List imageToRgb(img.Image src, int width, int height) {
  final im = img.copyResize(src, width: width, height: height);
  final out = Uint8List(width * height * 3);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = im.getPixel(x, y);
      out[i++] = p.r.toInt();
      out[i++] = p.g.toInt();
      out[i++] = p.b.toInt();
    }
  }
  return out;
}

/// Re-encode any decoded image/animation as a GIF at panel resolution (cmd 0x0003 payload).
Uint8List gifForPanel(img.Image src, int width, int height) {
  img.Image? anim;
  for (final f in src.frames) {
    final r = img.copyResize(f, width: width, height: height)
      ..frameDuration = f.frameDuration == 0 ? 100 : f.frameDuration;
    if (anim == null) {
      anim = r;
    } else {
      anim.addFrame(r);
    }
  }
  return img.encodeGif(anim!);
}

/// Decode bytes of any supported format (PNG/JPEG/GIF/BMP/WebP…).
img.Image? decodeAny(List<int> bytes) => img.decodeImage(Uint8List.fromList(bytes));
