import 'dart:math' as math;

import '../canvas.dart';
import '../fonts.dart';
import '../scene.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// Big digital clock. Fills the panel height with the largest fitting font.
class DigitalClockScene extends SimpleScene {
  bool seconds, h24, showDate, blinkColon;
  DigitalClockScene({super.color = 0xFFB000, this.seconds = false, this.h24 = true, this.showDate = false,
      this.blinkColon = true});
  @override
  String get name => 'Digital clock';
  @override
  double get fps => 2;
  final _date = Marquee('', pxPerSec: 10);

  @override
  void setParam(String key, Object value) {
    super.setParam(key, value);
    if (key == 'seconds' && value is bool) seconds = value;
    if (key == 'date' && value is bool) showDate = value;
    if (key == 'h24' && value is bool) h24 = value;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final now = DateTime.now();
    var h = now.hour;
    if (!h24) h = h % 12 == 0 ? 12 : h % 12;
    final colon = !blinkColon || now.second.isEven ? ':' : ' ';
    var s = '${_two(h)}$colon${_two(now.minute)}${seconds ? '$colon${_two(now.second)}' : ''}';
    final rowsForDate = showDate ? PixelFont.tiny.h + 1 : 0;
    var font = PixelFont.fitting(c.height - rowsForDate);
    var scale = 1;
    while (font.textWidth(s, scale: scale) > c.width && scale > 1) {
      scale--;
    }
    while (font.textWidth(s) > c.width) {
      font = font == PixelFont.large ? PixelFont.medium : font == PixelFont.medium ? PixelFont.small : PixelFont.tiny;
      if (font == PixelFont.tiny) break;
    }
    if (font.textWidth(s) > c.width && seconds) s = '${_two(h)}$colon${_two(now.minute)}';
    // scale up if there is room (e.g. 64x64 panels)
    while (font.textWidth(s, scale: scale + 1) <= c.width && font.h * (scale + 1) <= c.height - rowsForDate) {
      scale++;
    }
    final y = ((c.height - rowsForDate - font.h * scale) / 2).floor();
    font.drawCentered(c, s, color, y: y, scale: scale);
    if (showDate) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      _date.text = '${days[now.weekday - 1]} ${now.day}/${now.month}';
      _date.draw(c, c.height - PixelFont.tiny.h, dim(color, 0.6), dt);
    }
  }
}

/// Analog clock face (uses the panel height as diameter) with digital time beside it when wide.
class AnalogClockScene extends SimpleScene {
  AnalogClockScene({super.color = 0xFFFFFF});
  @override
  String get name => 'Analog clock';
  @override
  double get fps => 1;
  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final now = DateTime.now();
    final r = (math.min(c.width, c.height) - 1) ~/ 2;
    final cx = c.width > c.height * 2 ? r : c.width ~/ 2, cy = c.height ~/ 2;
    c.circle(cx, cy, r, dim(color, 0.25));
    for (var i = 0; i < 12; i += 3) {
      final a = i / 12 * 2 * math.pi;
      c.set(cx + (math.sin(a) * r).round(), cy - (math.cos(a) * r).round(), dim(color, 0.7));
    }
    void hand(double frac, double len, int col) {
      final a = frac * 2 * math.pi;
      c.line(cx, cy, cx + (math.sin(a) * r * len).round(), cy - (math.cos(a) * r * len).round(), col);
    }
    hand((now.hour % 12 + now.minute / 60) / 12, 0.55, color);
    hand(now.minute / 60, 0.9, color);
    hand(now.second / 60, 0.95, 0xFF3030);
    if (c.width > c.height * 2) {
      final s = '${_two(now.hour)}:${_two(now.minute)}';
      final f = PixelFont.fitting(c.height);
      final x = cx + r + 3;
      f.draw(c, s, x + ((c.width - x) - f.textWidth(s)) ~/ 2, (c.height - f.h) ~/ 2, color);
    }
  }
}

/// BCD binary clock: columns of bits for H H M M S S.
class BinaryClockScene extends SimpleScene {
  BinaryClockScene({super.color = 0x00E0FF});
  @override
  String get name => 'Binary clock';
  @override
  double get fps => 2;
  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final now = DateTime.now();
    final digits = [now.hour ~/ 10, now.hour % 10, now.minute ~/ 10, now.minute % 10, now.second ~/ 10, now.second % 10];
    final cell = math.max(1, math.min(c.height ~/ 4, c.width ~/ 9));
    final gap = cell > 2 ? 1 : 0;
    final totalW = 6 * cell + 5 * gap + 2 * (cell + gap); // extra gaps between pairs
    final x0 = (c.width - totalW) ~/ 2, y0 = (c.height - 4 * cell - 3 * gap) ~/ 2;
    var x = x0;
    for (var i = 0; i < 6; i++) {
      for (var bit = 0; bit < 4; bit++) {
        final on = (digits[i] >> bit) & 1 == 1;
        c.fillRect(x, y0 + (3 - bit) * (cell + gap), cell, cell, on ? color : dim(color, 0.12));
      }
      x += cell + gap + (i.isOdd ? cell + gap : 0);
    }
  }
}

/// Pomodoro / countdown timer. action = start/pause, back = reset, up/down = +/- 1 min.
class TimerScene extends SimpleScene {
  int totalSec;
  double _left;
  bool _running = false, _done = false;
  TimerScene({this.totalSec = 25 * 60, super.color = 0xFF5050}) : _left = (25 * 60).toDouble() {
    _left = totalSec.toDouble();
  }
  @override
  String get name => 'Timer';
  @override
  double get fps => 4;

  @override
  bool onInput(SceneInput input) {
    final i = input;
    switch (i) {
      case SceneInput.action:
        if (_done) {
          _left = totalSec.toDouble();
          _done = false;
        } else {
          _running = !_running;
        }
      case SceneInput.back:
        _running = false;
        _done = false;
        _left = totalSec.toDouble();
      case SceneInput.up:
        totalSec += 60;
        _left += 60;
      case SceneInput.down:
        if (totalSec > 60) {
          totalSec -= 60;
          _left = math.max(0, _left - 60);
        }
      default:
        return false;
    }
    return true;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    if (_running) {
      _left -= dt;
      if (_left <= 0) {
        _left = 0;
        _running = false;
        _done = true;
      }
    }
    if (_done && (t * 2).floor().isEven) c.clear(dim(color, 0.4));
    final m = _left ~/ 60, s = _left.floor() % 60;
    final txt = '${_two(m)}:${_two(s)}';
    final f = PixelFont.fitting(c.height - 2);
    f.drawCentered(c, txt, _done ? 0xFFFFFF : color, y: 0);
    final w = (c.width * _left / totalSec).round();
    c.fillRect(0, c.height - 1, w, 1, _running ? 0x40FF40 : dim(color, 0.6));
  }
}

/// Stopwatch: action = start/stop, back = reset.
class StopwatchScene extends SimpleScene {
  double _t = 0;
  bool _running = false;
  StopwatchScene({super.color = 0x40FF40});
  @override
  String get name => 'Stopwatch';
  @override
  double get fps => 10;
  @override
  bool onInput(SceneInput input) {
    final i = input;
    if (i == SceneInput.action) _running = !_running;
    if (i == SceneInput.back) {
      _running = false;
      _t = 0;
    }
    return i == SceneInput.action || i == SceneInput.back;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    if (_running) _t += dt;
    c.clear();
    final m = _t ~/ 60, s = _t.floor() % 60, ds = ((_t * 10) % 10).floor();
    final txt = m > 0 ? '${_two(m)}:${_two(s)}.$ds' : '${_two(s)}.$ds';
    PixelFont.fitting(c.height).drawCentered(c, txt, _running ? color : 0xFFFFFF);
  }
}
