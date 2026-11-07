import 'dart:math' as math;

import '../canvas.dart';
import '../fonts.dart';
import '../icons.dart';
import '../scene.dart';

/// Text with a style. Styles: scroll, rainbow, typewriter, blink, bounce, wave, static.
class TextFxScene extends SimpleScene {
  String text;
  String style;
  double speed;
  int bg;
  final _m = Marquee('');
  TextFxScene({this.text = 'HELLO', this.style = 'rainbow', this.speed = 20, super.color = 0xFFFFFF, this.bg = 0});
  @override
  String get name => 'Text effects';
  @override
  double get fps => 12;
  static const styles = ['scroll', 'rainbow', 'typewriter', 'blink', 'bounce', 'wave', 'static', 'fire'];

  @override
  void setParam(String key, Object value) {
    final v = value;
    super.setParam(key, v);
    if (key == 'text' && v is String) text = v;
    if (key == 'style' && v is String) style = v;
    if (key == 'speed' && v is num) speed = v.toDouble();
    if (key == 'bg' && v is int) bg = v;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear(bg);
    final f = PixelFont.fitting(c.height);
    final y = (c.height - f.h) ~/ 2;
    final tw = f.textWidth(text);
    switch (style) {
      case 'scroll':
        _m
          ..text = text
          ..draw(c, y, color, dt * speed / 20);
      case 'rainbow':
        final x0 = tw <= c.width ? (c.width - tw) ~/ 2 : (c.width - (t * speed) % (tw + c.width)).floor();
        for (var i = 0; i < text.length; i++) {
          f.draw(c, text[i], x0 + i * f.w, y, hsv(i * 30 + t * 90));
        }
      case 'typewriter':
        final n = ((t * speed / 5) % (text.length + 3)).floor().clamp(0, text.length);
        f.draw(c, text.substring(0, n), math.max(0, (c.width - tw) ~/ 2), y, color);
        if ((t * 3).floor().isEven && n < text.length) c.fillRect(math.max(0, (c.width - tw) ~/ 2) + n * f.w, y, f.w - 1, f.h, dim(color, 0.6));
      case 'blink':
        if ((t * speed / 10).floor().isEven) f.drawCentered(c, text, color, y: y);
      case 'bounce':
        final x = ((math.sin(t * speed / 10) + 1) / 2 * (c.width - tw)).round();
        f.draw(c, text, tw <= c.width ? x : x.clamp(c.width - tw, 0), y, color);
      case 'wave':
        final x0 = tw <= c.width ? (c.width - tw) ~/ 2 : (c.width - (t * speed) % (tw + c.width)).floor();
        for (var i = 0; i < text.length; i++) {
          final dy = (math.sin(t * 5 + i * 0.8) * math.max(1, (c.height - f.h) / 2)).round();
          f.draw(c, text[i], x0 + i * f.w, y + dy, color);
        }
      case 'fire':
        final x0 = (c.width - tw) ~/ 2;
        for (var i = 0; i < text.length; i++) {
          for (var gy = 0; gy < f.h; gy++) {
            for (var gx = 0; gx < f.w; gx++) {
              if (f.pixel(text.codeUnitAt(i), gx, gy)) {
                final heat = (1 - gy / f.h) * 0.6 + rng.nextDouble() * 0.4;
                c.set(x0 + i * f.w + gx, y + gy, heat > 0.8 ? 0xFFFF80 : heat > 0.5 ? 0xFF8000 : 0xC02000);
              }
            }
          }
        }
      default:
        f.drawCentered(c, text, color, y: y);
    }
  }
}

/// Ready-made signs with an icon: ON AIR, OPEN, CLOSED, BUSY, BRB, REC, …
class SignScene extends SimpleScene {
  String text;
  List<int>? icon;
  bool pulse;
  SignScene(this.text, {this.icon, super.color = 0xFF2020, this.pulse = true});
  @override
  String get name => text;
  @override
  double get fps => 6;

  static List<SignScene> presets() => [
        SignScene('ON AIR', icon: Icons8.mic, color: 0xFF2020),
        SignScene('REC', icon: Icons8.mic, color: 0xFF0000),
        SignScene('OPEN', icon: Icons8.check, color: 0x20FF40, pulse: false),
        SignScene('CLOSED', icon: Icons8.cross, color: 0xFF4040, pulse: false),
        SignScene('BUSY', icon: Icons8.bolt, color: 0xFFA000),
        SignScene('BRB', icon: Icons8.coffee, color: 0x40C0FF, pulse: false),
        SignScene('DND', icon: Icons8.bell, color: 0xC040FF, pulse: false),
        SignScene('MEETING', icon: Icons8.mail, color: 0xFF6000, pulse: false),
        SignScene('BOO!', icon: Icons8.ghost, color: 0xC0C0FF),
        SignScene('LOVE', icon: Icons8.heart, color: 0xFF3070),
      ];

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final k = pulse ? 0.65 + 0.35 * math.sin(t * 3) : 1.0;
    final col = dim(color, k);
    final f = PixelFont.fitting(c.height);
    var x = 1;
    if (icon != null && c.width >= 32) {
      Icons8.draw(c, icon!, x, (c.height - 8) ~/ 2, col);
      x += 10;
    }
    final tw = f.textWidth(text);
    f.draw(c, text, x + math.max(0, (c.width - x - tw) ~/ 2), (c.height - f.h) ~/ 2, col);
  }
}

/// Scrolling parade of icons.
class IconParadeScene extends SimpleScene {
  @override
  String get name => 'Icon parade';
  @override
  double get fps => 12;
  late final _icons = Icons8.all.values.toList();
  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final step = 11, total = _icons.length * step;
    final off = (t * 12) % total;
    for (var i = 0; i < _icons.length; i++) {
      final x = (i * step - off).round();
      final xx = x < -10 ? x + total : x;
      if (xx < c.width) Icons8.draw(c, _icons[i], xx, (c.height - 8) ~/ 2, hsv(i * 25.0, 0.8));
    }
  }
}

/// A picture (any image) shown with a Ken-Burns style slow pan when it is larger than the panel.
class PictureScene extends Scene {
  final dynamic image; // img.Image
  final bool pan;
  PictureScene(this.image, {this.pan = true});
  @override
  String get name => 'Picture';
  @override
  double get fps => pan ? 4 : 1;
  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    c.drawImage(image);
  }
}
