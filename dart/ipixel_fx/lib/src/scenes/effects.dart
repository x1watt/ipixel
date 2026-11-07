import 'dart:math' as math;

import '../canvas.dart';
import '../scene.dart';

/// Classic sine plasma.
class PlasmaScene extends SimpleScene {
  @override
  String get name => 'Plasma';
  @override
  void draw(PanelCanvas c, double t, double dt) {
    for (var y = 0; y < c.height; y++) {
      for (var x = 0; x < c.width; x++) {
        final v = math.sin(x / 6 + t) +
            math.sin((y / 4 + t * 0.7)) +
            math.sin((x + y) / 8 + t * 1.3) +
            math.sin(math.sqrt(x * x + y * y) / 5 - t);
        c.set(x, y, hsv((v + 4) / 8 * 360 + t * 20));
      }
    }
  }
}

/// Doom-style fire rising from the bottom.
class FireScene extends SimpleScene {
  @override
  String get name => 'Fire';
  @override
  double get fps => 12;
  late List<int> _heat;
  late int _w, _h;
  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _heat = List.filled(_w * _h, 0);
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    for (var x = 0; x < _w; x++) {
      _heat[(_h - 1) * _w + x] = rng.nextInt(64) + 191;
    }
    for (var y = 0; y < _h - 1; y++) {
      for (var x = 0; x < _w; x++) {
        final sx = (x + rng.nextInt(3) - 1).clamp(0, _w - 1);
        _heat[y * _w + x] = math.max(0, _heat[(y + 1) * _w + sx] - rng.nextInt(28));
      }
    }
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final h = _heat[y * _w + x];
        c.set(x, y, h < 85 ? rgb(h * 3, 0, 0) : h < 170 ? rgb(255, (h - 85) * 3, 0) : rgb(255, 255, (h - 170) * 3));
      }
    }
  }
}

/// Falling code in the film's palette: pale head, #00FF41 body, fading to dark green.
class MatrixScene extends SimpleScene {
  MatrixScene() : super(color: 0x00FF41);
  @override
  String get name => 'Matrix';
  @override
  double get fps => 10;
  late List<double> _y, _speed;
  @override
  void init(int width, int height) {
    _y = List.generate(width, (_) => rng.nextDouble() * height * 2 - height);
    _speed = List.generate(width, (_) => 6 + rng.nextDouble() * 14);
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    // fade red/blue faster than green so trails stay green
    final b = c.rgbBytes;
    for (var i = 0; i < b.length; i += 3) {
      b[i] = (b[i] * 0.45).floor();
      b[i + 1] = (b[i + 1] * 0.78).floor();
      b[i + 2] = (b[i + 2] * 0.45).floor();
    }
    for (var x = 0; x < c.width; x++) {
      _y[x] += _speed[x] * dt;
      if (_y[x] > c.height + 4) {
        _y[x] = -rng.nextInt(c.height * 2).toDouble();
        _speed[x] = 6 + rng.nextDouble() * 14;
      }
      final y = _y[x].floor();
      c.set(x, y, 0xC8FFC8); // pale head
      c.set(x, y - 1, color); // #00FF41
    }
  }
}

/// Diagonal rainbow wave.
class RainbowScene extends SimpleScene {
  @override
  String get name => 'Rainbow';
  @override
  void draw(PanelCanvas c, double t, double dt) {
    for (var y = 0; y < c.height; y++) {
      for (var x = 0; x < c.width; x++) {
        c.set(x, y, hsv((x * 4 + y * 6 - t * 120)));
      }
    }
  }
}

/// Flying through white stars (brightness by distance, slight twinkle).
class StarfieldScene extends SimpleScene {
  StarfieldScene({super.color = 0xFFFFFF});
  @override
  String get name => 'Starfield';
  @override
  double get fps => 12;
  final _stars = <List<double>>[]; // x,y,z,tint
  @override
  void init(int width, int height) {
    for (var i = 0; i < 45; i++) {
      _stars.add([rng.nextDouble() * 2 - 1, rng.nextDouble() * 2 - 1, rng.nextDouble(), rng.nextDouble()]);
    }
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    for (final s in _stars) {
      s[2] -= dt * 0.25;
      if (s[2] <= 0.02) {
        s[0] = rng.nextDouble() * 2 - 1;
        s[1] = rng.nextDouble() * 2 - 1;
        s[2] = 1;
      }
      final px = (c.width / 2 + s[0] / s[2] * c.width / 2).round();
      final py = (c.height / 2 + s[1] / s[2] * c.height / 2).round();
      final twinkle = 0.85 + 0.15 * math.sin(t * 6 + s[3] * 40);
      final k = ((1 - s[2]) * twinkle).clamp(0.08, 1.0);
      // real stars: white, a few faintly warm or cool
      final tint = s[3] < 0.15 ? 0xFFF0D0 : s[3] > 0.85 ? 0xD8E8FF : 0xFFFFFF;
      c.set(px, py, dim(tint, k));
    }
  }
}

/// Warp speed: stars streak outward from the centre, with periodic jumps to warp.
class WarpScene extends SimpleScene {
  WarpScene({super.color = 0xFFFFFF});
  @override
  String get name => 'Warp';
  @override
  double get fps => 15;
  final _stars = <List<double>>[]; // angle, dist (0..1), speed, tint
  double _warp = 0; // 0 cruise .. 1 full warp
  @override
  void init(int width, int height) {
    for (var i = 0; i < 60; i++) {
      _stars.add([rng.nextDouble() * math.pi * 2, rng.nextDouble(), 0.3 + rng.nextDouble(), rng.nextDouble()]);
    }
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    // 6 s cruise, 2 s ramp, 6 s warp, 2 s ramp down
    final phase = t % 16;
    _warp = phase < 6 ? 0 : phase < 8 ? (phase - 6) / 2 : phase < 14 ? 1 : (16 - phase) / 2;
    c.fade(0.35);
    final cx = c.width / 2, cy = c.height / 2;
    final rx = c.width / 2 + 2, ry = c.height / 2 + 2;
    final stretch = 1 + _warp * 10;
    for (final s in _stars) {
      final d0 = s[1];
      s[1] += dt * s[2] * (0.25 + _warp * 1.8) * (0.3 + s[1]);
      if (s[1] > 1.2) {
        s[0] = rng.nextDouble() * math.pi * 2;
        s[1] = 0.02 + rng.nextDouble() * 0.1;
        s[2] = 0.3 + rng.nextDouble();
      }
      final tail = (s[1] - (s[1] - d0) * stretch).clamp(0.0, 1.2);
      final x0 = (cx + math.cos(s[0]) * tail * rx).round(), y0 = (cy + math.sin(s[0]) * tail * ry).round();
      final x1 = (cx + math.cos(s[0]) * s[1] * rx).round(), y1 = (cy + math.sin(s[0]) * s[1] * ry).round();
      final k = (0.2 + s[1] * 0.8).clamp(0.0, 1.0);
      final tint = _warp > 0.5 ? mix(color, 0xA0C8FF, _warp - 0.5) : color;
      c.line(x0, y0, x1, y1, dim(tint, k));
    }
  }
}

/// Random coloured sparkles with trails.
class SparkleScene extends SimpleScene {
  @override
  String get name => 'Sparkle';
  @override
  double get fps => 10;
  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.fade(0.8);
    for (var i = 0; i < c.width * c.height ~/ 40 + 1; i++) {
      c.set(rng.nextInt(c.width), rng.nextInt(c.height), hsv(rng.nextDouble() * 360, 0.7));
    }
  }
}

/// Bouncing balls that light up where they hit.
class BallsScene extends SimpleScene {
  @override
  String get name => 'Bouncing balls';
  @override
  double get fps => 12;
  final _b = <List<double>>[]; // x,y,vx,vy,hue
  @override
  void init(int width, int height) {
    for (var i = 0; i < 5; i++) {
      _b.add([rng.nextDouble() * width, rng.nextDouble() * height, rng.nextDouble() * 20 - 10,
        rng.nextDouble() * 12 - 6, i * 72.0]);
    }
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.fade(0.6);
    for (final b in _b) {
      b[0] += b[2] * dt;
      b[1] += b[3] * dt;
      if (b[0] < 0 || b[0] >= c.width) b[2] = -b[2];
      if (b[1] < 0 || b[1] >= c.height) b[3] = -b[3];
      b[0] = b[0].clamp(0, c.width - 1.0);
      b[1] = b[1].clamp(0, c.height - 1.0);
      c.set(b[0].round(), b[1].round(), hsv(b[4]));
    }
  }
}

/// Conway's Game of Life, reseeded when it dies out.
class LifeScene extends SimpleScene {
  LifeScene() : super(color: 0x40C0FF);
  @override
  String get name => 'Game of Life';
  @override
  double get fps => 6;
  late List<bool> _g;
  late int _w, _h;
  int _still = 0;
  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _seed();
  }

  void _seed() => _g = List.generate(_w * _h, (_) => rng.nextDouble() < 0.3);

  @override
  void draw(PanelCanvas c, double t, double dt) {
    final n = List<bool>.filled(_w * _h, false);
    var alive = 0, changed = 0;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        var k = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if ((dx != 0 || dy != 0) && _g[((y + dy + _h) % _h) * _w + (x + dx + _w) % _w]) k++;
          }
        }
        final a = _g[y * _w + x];
        n[y * _w + x] = a ? (k == 2 || k == 3) : k == 3;
        if (n[y * _w + x]) alive++;
        if (n[y * _w + x] != a) changed++;
      }
    }
    _still = changed == 0 ? _still + 1 : 0;
    _g = n;
    if (alive == 0 || _still > 5) _seed();
    for (var i = 0; i < _g.length; i++) {
      c.set(i % _w, i ~/ _w, _g[i] ? color : 0);
    }
  }
}

/// Lava lamp made of metaballs.
class LavaScene extends SimpleScene {
  @override
  String get name => 'Lava lamp';
  @override
  void draw(PanelCanvas c, double t, double dt) {
    final blobs = [
      for (var i = 0; i < 4; i++)
        (c.width / 2 + math.sin(t * 0.6 + i * 1.7) * c.width / 2.5, c.height / 2 + math.cos(t * 0.8 + i * 2.1) * c.height / 2.5)
    ];
    for (var y = 0; y < c.height; y++) {
      for (var x = 0; x < c.width; x++) {
        var v = 0.0;
        for (final (bx, by) in blobs) {
          v += 12 / (1 + (x - bx) * (x - bx) / 4 + (y - by) * (y - by));
        }
        c.set(x, y, v > 2.5 ? hsv(300 + v * 8, 0.9) : v > 1.2 ? rgb(60, 0, 40) : 0);
      }
    }
  }
}
