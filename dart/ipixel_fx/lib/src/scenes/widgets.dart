import 'dart:io';
import 'dart:math' as math;

import '../canvas.dart';
import '../fonts.dart';
import '../icons.dart';
import '../scene.dart';

/// Scrolling ticker of messages. Feed it with setParam('text', …) or setParam('push', …).
class TickerScene extends SimpleScene {
  final List<String> queue = [];
  String text;
  final double speed;
  late final Marquee _m;
  TickerScene({this.text = 'Hello from iPixel Open', this.speed = 20, super.color = 0xFFFFFF}) {
    _m = Marquee(text, pxPerSec: speed, font: PixelFont.small);
  }
  @override
  String get name => 'Ticker';
  @override
  double get fps => 10;
  @override
  void setParam(String key, Object value) {
    super.setParam(key, value);
    if (key == 'text' && value is String) text = value;
    if (key == 'push' && value is String) queue.add(value);
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    _m.text = queue.isNotEmpty ? queue.first : text;
    final font = PixelFont.fitting(c.height);
    final m = Marquee(_m.text, font: font, pxPerSec: speed)..offset = _m.offset;
    m.draw(c, (c.height - font.h) ~/ 2, color, dt);
    _m.offset = m.offset;
    if (queue.isNotEmpty && m.offset < speed * dt * 1.5 && t > 1) queue.removeAt(0); // wrapped: next message
  }
}

/// Live system load (Linux /proc on desktop; elsewhere feed 'cpu'/'mem' params 0..1).
class SystemStatsScene extends SimpleScene {
  double cpu = 0, mem = 0;
  int _lastIdle = 0, _lastTotal = 0;
  final _hist = <double>[];
  SystemStatsScene({super.color = 0x40FF80});
  @override
  String get name => 'System monitor';
  @override
  double get fps => 2;
  @override
  void setParam(String key, Object value) {
    super.setParam(key, value);
    if (key == 'cpu' && value is num) cpu = value.toDouble();
    if (key == 'mem' && value is num) mem = value.toDouble();
  }

  void _sample() {
    if (!Platform.isLinux) return;
    try {
      final l = File('/proc/stat').readAsLinesSync().first.split(RegExp(r'\s+')).skip(1).map(int.parse).toList();
      final idle = l[3] + l[4], total = l.fold(0, (a, b) => a + b);
      if (_lastTotal > 0 && total > _lastTotal) cpu = 1 - (idle - _lastIdle) / (total - _lastTotal);
      _lastIdle = idle;
      _lastTotal = total;
      final mi = {for (final ln in File('/proc/meminfo').readAsLinesSync().take(5)) ln.split(':')[0]: int.parse(ln.split(RegExp(r'\s+'))[1])};
      mem = 1 - (mi['MemAvailable'] ?? 0) / (mi['MemTotal'] ?? 1);
    } catch (_) {}
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    _sample();
    _hist.add(cpu);
    while (_hist.length > c.width ~/ 2) {
      _hist.removeAt(0);
    }
    c.clear();
    final f = PixelFont.tiny;
    f.draw(c, 'CPU${(cpu * 100).round().toString().padLeft(3)}', 0, 0, color);
    f.draw(c, 'MEM${(mem * 100).round().toString().padLeft(3)}', 0, c.height - f.h, 0x40A0FF);
    final gx = c.width ~/ 2;
    for (var i = 0; i < _hist.length; i++) {
      final h = (_hist[i] * c.height).round();
      c.fillRect(gx + i, c.height - h, 1, h, hsv(120 - _hist[i] * 120));
    }
  }
}

/// Progress bar with a label; setParam('value', 0..1) and setParam('text', …).
class ProgressScene extends SimpleScene {
  double value;
  String text;
  ProgressScene({this.value = 0.42, this.text = 'build', super.color = 0x40C0FF});
  @override
  String get name => 'Progress bar';
  @override
  double get fps => 4;
  @override
  void setParam(String key, Object value) {
    final v = value;
    super.setParam(key, v);
    if (key == 'value' && v is num) value = v.toDouble().clamp(0, 1);
    if (key == 'text' && v is String) text = v;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final f = PixelFont.tiny;
    final label = '$text ${(value * 100).round()}%';
    f.draw(c, label, 1, 0, 0xFFFFFF);
    final by = f.h + 1, bh = math.max(2, c.height - by - 1);
    c.rect(0, by, c.width, bh, dim(color, 0.4));
    final w = ((c.width - 2) * value).round();
    for (var x = 0; x < w; x++) {
      c.fillRect(1 + x, by + 1, 1, bh - 2, mix(color, 0x40FF80, x / c.width));
    }
    final shine = ((t * 30) % (c.width + 10)).round() - 5;
    if (shine >= 1 && shine < 1 + w) c.fillRect(shine, by + 1, 1, bh - 2, 0xFFFFFF);
  }
}

/// Audio meter driven by setParam('level', 0..1) or setParam('spectrum', a list of doubles).
class VuMeterScene extends SimpleScene {
  double level = 0;
  List<double> spectrum = const [];
  final _peaks = <double>[];
  VuMeterScene({super.color = 0x40FF40});
  @override
  String get name => 'Music meter';
  @override
  double get fps => 15;
  @override
  void setParam(String key, Object value) {
    final v = value;
    super.setParam(key, v);
    if (key == 'level' && v is num) level = v.toDouble().clamp(0, 1);
    if (key == 'spectrum' && v is List) spectrum = v.map((e) => (e as num).toDouble().clamp(0.0, 1.0)).toList();
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final bars = spectrum.isNotEmpty ? spectrum : List.generate(16, (i) => (level * (1 - i / 24) * (0.7 + 0.3 * math.sin(t * 7 + i))).clamp(0.0, 1.0));
    while (_peaks.length < bars.length) {
      _peaks.add(0);
    }
    final bw = math.max(1, c.width ~/ bars.length);
    for (var i = 0; i < bars.length; i++) {
      final h = (bars[i] * c.height).round();
      _peaks[i] = math.max(_peaks[i] - dt * 8, h.toDouble());
      for (var y = 0; y < h; y++) {
        c.fillRect(i * bw, c.height - 1 - y, bw - (bw > 2 ? 1 : 0), 1, hsv(120 - 120 * y / c.height));
      }
      c.fillRect(i * bw, c.height - 1 - _peaks[i].round(), bw - (bw > 2 ? 1 : 0), 1, 0xFFFFFF);
    }
  }
}

/// Days/hours countdown to a date, e.g. a launch or a birthday.
class CountdownScene extends SimpleScene {
  DateTime target;
  String label;
  CountdownScene({DateTime? target, this.label = 'NEW YEAR', super.color = 0xFF60C0})
      : target = target ?? DateTime(DateTime.now().year + 1, 1, 1);
  @override
  String get name => 'Countdown to date';
  @override
  double get fps => 1;
  @override
  void setParam(String key, Object value) {
    final v = value;
    super.setParam(key, v);
    if (key == 'target' && v is DateTime) target = v;
    if (key == 'text' && v is String) label = v;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    final d = target.difference(DateTime.now());
    final txt = d.isNegative
        ? 'NOW!'
        : d.inDays > 0
            ? '${d.inDays}d ${d.inHours % 24}h'
            : '${d.inHours}h ${d.inMinutes % 60}m';
    PixelFont.tiny.drawCentered(c, label, dim(color, 0.6), y: 0);
    PixelFont.fitting(c.height - PixelFont.tiny.h - 1).drawCentered(c, txt, color, y: PixelFont.tiny.h + 1);
  }
}

/// Icon + value pairs, e.g. unread mail / temperature. setParam('items', [['mail', '3'], ['sun', '21C']]).
class StatusScene extends SimpleScene {
  List<(String, String)> items;
  StatusScene({this.items = const [('mail', '3'), ('bell', '1'), ('sun', '21C')], super.color = 0xFFFFFF});
  @override
  String get name => 'Status icons';
  @override
  double get fps => 2;
  @override
  void setParam(String key, Object value) {
    final v = value;
    super.setParam(key, v);
    if (key == 'items' && v is List) items = [for (final e in v) ((e as List)[0] as String, e[1] as String)];
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear();
    var x = 1;
    final f = PixelFont.tiny;
    for (final (icon, value) in items) {
      final bmp = Icons8.all[icon];
      if (bmp != null) Icons8.draw(c, bmp, x, (c.height - 8) ~/ 2, hsv(items.indexOf((icon, value)) * 60.0, 0.6));
      x += 9;
      f.draw(c, value, x, (c.height - f.h) ~/ 2, color);
      x += f.textWidth(value) + 4;
      if (x > c.width) break;
    }
  }
}
