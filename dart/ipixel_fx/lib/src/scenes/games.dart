import 'dart:math' as math;

import '../canvas.dart';
import '../fonts.dart';
import '../scene.dart';

void _gameOver(PanelCanvas c, int score) {
  c.clear();
  final f = PixelFont.fitting(c.height ~/ 2);
  f.drawCentered(c, 'GAME OVER', 0xFF4040, y: 0);
  f.drawCentered(c, '$score', 0xFFFFFF, y: f.h + 1);
}

/// Base for games: an auto-player takes over after [idleSeconds] without input, or always
/// when `setParam('auto', true)`. Any real input hands control back.
abstract class GameScene extends Scene {
  bool autoplay = false;
  double _lastInput = -100, _now = 0;
  double get idleSeconds => 3;
  bool get autoPilot => autoplay || _now - _lastInput > idleSeconds;

  @override
  void setParam(String key, Object value) {
    if (key == 'auto' && value is bool) autoplay = value;
  }

  /// Subclasses call this at the start of draw().
  void tick(double t) => _now = t;

  /// Subclasses call this from onInput for real (non-auto) input.
  void touched() {
    _lastInput = _now;
    autoplay = false;
  }

  /// Restart after a game over when nobody is playing.
  double _deadSince = -1;
  bool autoRestart(bool dead, double t) {
    if (!dead) {
      _deadSince = -1;
      return false;
    }
    _deadSince = _deadSince < 0 ? t : _deadSince;
    return autoPilot && t - _deadSince > 2.5;
  }
}

/// Snake. Arrows steer, action restarts.
class SnakeScene extends GameScene {
  @override
  String get name => 'Snake';
  @override
  double get fps => 6;
  late int _w, _h;
  var _body = <(int, int)>[];
  var _dir = (1, 0), _next = (1, 0);
  late (int, int) _food;
  bool _dead = false;
  int _score = 0;

  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _reset();
  }

  void _reset() {
    _body = [(_w ~/ 2, _h ~/ 2), (_w ~/ 2 - 1, _h ~/ 2), (_w ~/ 2 - 2, _h ~/ 2)];
    _dir = _next = (1, 0);
    _dead = false;
    _score = 0;
    _spawn();
  }

  void _spawn() {
    do {
      _food = (rng.nextInt(_w), rng.nextInt(_h));
    } while (_body.contains(_food));
  }

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];

  @override
  bool onInput(SceneInput input) {
    touched();
    final d = switch (input) {
      SceneInput.up => (0, -1),
      SceneInput.down => (0, 1),
      SceneInput.left => (-1, 0),
      SceneInput.right => (1, 0),
      _ => null,
    };
    if (input == SceneInput.action && _dead) _reset();
    if (d == null || (d.$1 == -_dir.$1 && d.$2 == -_dir.$2)) return d == null;
    _next = d;
    return true;
  }

  (int, int) _step((int, int) p, (int, int) d) => ((p.$1 + d.$1 + _w) % _w, (p.$2 + d.$2 + _h) % _h);

  int _freeAround((int, int) p) => _dirs.where((d) => !_body.contains(_step(p, d))).length;

  void _autoSteer() {
    final head = _body.first;
    var best = _dir;
    var bestScore = -1e9;
    for (final d in _dirs) {
      if (d.$1 == -_dir.$1 && d.$2 == -_dir.$2) continue;
      final n = _step(head, d);
      if (_body.contains(n) && n != _body.last) continue; // tail moves away, so it's safe
      final dx = math.min((n.$1 - _food.$1).abs(), _w - (n.$1 - _food.$1).abs());
      final dy = math.min((n.$2 - _food.$2).abs(), _h - (n.$2 - _food.$2).abs());
      final score = -(dx + dy) * 1.0 + _freeAround(n) * 2.5 + (d == _dir ? 0.3 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    _next = best;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    tick(t);
    if (_dead) {
      _gameOver(c, _score);
      if (autoRestart(true, t)) _reset();
      return;
    }
    if (autoPilot) _autoSteer();
    _dir = _next;
    final head = _step(_body.first, _dir);
    if (_body.contains(head) && head != _body.last) {
      _dead = true;
      return;
    }
    _body.insert(0, head);
    if (head == _food) {
      _score++;
      _spawn();
    } else {
      _body.removeLast();
    }
    c.clear();
    for (var i = 0; i < _body.length; i++) {
      c.set(_body[i].$1, _body[i].$2, i == 0 ? 0xFFFFFF : hsv(100 + i * 3, 0.9, 1 - i / (_body.length + 8)));
    }
    c.set(_food.$1, _food.$2, (t * 4).floor().isEven ? 0xFF2020 : 0xFF8000);
  }
}

/// Pong. up/down move the left paddle; the auto-player takes over when idle.
class PongScene extends GameScene {
  @override
  String get name => 'Pong';
  @override
  double get fps => 15;
  late int _w, _h;
  double _bx = 0, _by = 0, _vx = 20, _vy = 9, _p1 = 0, _p2 = 0;
  int _s1 = 0, _s2 = 0;
  int get _ph => math.max(3, _h ~/ 4);

  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _p1 = _p2 = (height - _ph) / 2;
    _serve();
  }

  void _serve() {
    _bx = _w / 2;
    _by = _h / 2;
    _vx = (rng.nextBool() ? 1 : -1) * (14 + rng.nextDouble() * 6);
    _vy = (rng.nextDouble() - 0.5) * 16;
  }

  @override
  bool onInput(SceneInput input) {
    touched();
    if (input == SceneInput.up) _p1 = math.max(0, _p1 - 2);
    if (input == SceneInput.down) _p1 = math.min(_h - _ph.toDouble(), _p1 + 2);
    return input == SceneInput.up || input == SceneInput.down;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    tick(t);
    _bx += _vx * dt;
    _by += _vy * dt;
    if (_by < 0 || _by > _h - 1) {
      _vy = -_vy;
      _by = _by.clamp(0, _h - 1.0);
    }
    double follow(double p, double maxStep) => (p + ((_by - _ph / 2) - p).clamp(-maxStep, maxStep)).clamp(0, _h - _ph.toDouble());
    _p2 = follow(_p2, dt * 18);
    if (autoPilot) _p1 = follow(_p1, dt * 16); // slightly slower: rallies end eventually
    if (_bx <= 1 && _by >= _p1 - 1 && _by <= _p1 + _ph) {
      _vx = -_vx * 1.05;
      _bx = 1;
      _vy += (_by - (_p1 + _ph / 2)) * 3;
    }
    if (_bx >= _w - 2 && _by >= _p2 - 1 && _by <= _p2 + _ph) {
      _vx = -_vx * 1.05;
      _bx = _w - 2.0;
      _vy += (_by - (_p2 + _ph / 2)) * 3;
    }
    if (_bx < 0) {
      _s2++;
      _serve();
    }
    if (_bx > _w) {
      _s1++;
      _serve();
    }
    c.clear();
    for (var y = 0; y < _h; y += 2) {
      c.set(_w ~/ 2, y, 0x303030);
    }
    c.fillRect(0, _p1.round(), 1, _ph, 0x40C0FF);
    c.fillRect(_w - 1, _p2.round(), 1, _ph, 0xFF8040);
    c.set(_bx.round(), _by.round(), 0xFFFFFF);
    final f = PixelFont.tiny;
    f.draw(c, '$_s1', _w ~/ 2 - f.w - 2, 0, 0x40C0FF);
    f.draw(c, '$_s2', _w ~/ 2 + 2, 0, 0xFF8040);
  }
}

/// Breakout. left/right move the paddle; action launches / restarts.
class BreakoutScene extends GameScene {
  @override
  String get name => 'Breakout';
  @override
  double get fps => 15;
  late int _w, _h;
  late List<bool> _bricks;
  late int _rows, _cols, _bw;
  double _px = 0, _bx = 0, _by = 0, _vx = 0, _vy = 0, _idle = 0;
  bool _launched = false, _dead = false;
  int _score = 0, _lives = 3;
  int get _pw => math.max(3, _w ~/ 8);

  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _bw = width >= 32 ? 3 : 2;
    _cols = width ~/ (_bw + 1);
    _rows = math.max(2, height ~/ 5);
    _reset();
  }

  void _reset() {
    _bricks = List.filled(_rows * _cols, true);
    _score = 0;
    _lives = 3;
    _dead = false;
    _px = (_w - _pw) / 2;
    _launched = false;
  }

  void _launch() {
    _launched = true;
    _vx = (rng.nextDouble() - 0.5) * 20;
    _vy = -14;
  }

  @override
  bool onInput(SceneInput input) {
    touched();
    if (input == SceneInput.left) _px = math.max(0, _px - 2);
    if (input == SceneInput.right) _px = math.min(_w - _pw.toDouble(), _px + 2);
    if (input == SceneInput.action) {
      if (_dead) {
        _reset();
      } else if (!_launched) {
        _launch();
      }
    }
    return true;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    tick(t);
    if (_dead) {
      _gameOver(c, _score);
      if (autoRestart(true, t)) _reset();
      return;
    }
    if (autoPilot) {
      final target = _bx - _pw / 2 + (_vx > 0 ? 0.5 : -0.5);
      _px = (_px + (target - _px).clamp(-dt * 40, dt * 40)).clamp(0, _w - _pw.toDouble());
      _idle += dt;
      if (!_launched && _idle > 1) _launch();
    }
    if (!_launched) {
      _bx = _px + _pw / 2;
      _by = _h - 2.0;
    } else {
      _idle = 0;
      _bx += _vx * dt;
      _by += _vy * dt;
      if (_bx < 0 || _bx > _w - 1) {
        _vx = -_vx;
        _bx = _bx.clamp(0, _w - 1.0);
      }
      if (_by < 0) {
        _vy = -_vy;
        _by = 0;
      }
      if (_by >= _h - 2 && _bx >= _px - 1 && _bx <= _px + _pw) {
        _vy = -_vy.abs();
        _vx += (_bx - (_px + _pw / 2)) * 4;
        _by = _h - 2.0;
      }
      if (_by > _h) {
        _lives--;
        _launched = false;
        if (_lives == 0) _dead = true;
      }
      final r = _by.floor() ~/ 2, col = _bx.floor() ~/ (_bw + 1);
      if (r < _rows && col < _cols && _bricks[r * _cols + col]) {
        _bricks[r * _cols + col] = false;
        _vy = -_vy;
        _score += 10;
        if (!_bricks.contains(true)) _bricks = List.filled(_rows * _cols, true);
      }
    }
    c.clear();
    for (var r = 0; r < _rows; r++) {
      for (var col = 0; col < _cols; col++) {
        if (_bricks[r * _cols + col]) c.fillRect(col * (_bw + 1), r * 2, _bw, 1, hsv(r * 50.0));
      }
    }
    c.fillRect(_px.round(), _h - 1, _pw, 1, 0x40C0FF);
    c.set(_bx.round(), _by.round(), 0xFFFFFF);
    for (var i = 0; i < _lives; i++) {
      c.set(_w - 1 - i * 2, 0, 0xFF4040);
    }
  }
}

/// Flappy-style: action flaps, fly through the gaps.
class FlappyScene extends GameScene {
  @override
  String get name => 'Flappy';
  @override
  double get fps => 15;
  late int _w, _h;
  double _y = 0, _vy = 0;
  final _pipes = <List<double>>[]; // x, gapY
  int _score = 0;
  bool _dead = false, _started = false;
  int get _gap => math.max(4, _h ~/ 3);

  @override
  void init(int width, int height) {
    _w = width;
    _h = height;
    _reset();
  }

  void _reset() {
    _y = _h / 2;
    _vy = 0;
    _pipes.clear();
    for (var i = 0; i < 3; i++) {
      _pipes.add([_w + i * (_w / 2.5), 1 + rng.nextInt(math.max(1, _h - _gap - 2)).toDouble()]);
    }
    _score = 0;
    _dead = false;
    _started = false;
  }

  void _flap() {
    _started = true;
    _vy = -18;
  }

  @override
  bool onInput(SceneInput input) {
    touched();
    if (input == SceneInput.action || input == SceneInput.up) {
      _dead ? _reset() : _flap();
      return true;
    }
    return false;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    tick(t);
    if (_dead) {
      _gameOver(c, _score);
      if (autoRestart(true, t)) _reset();
      return;
    }
    if (autoPilot) {
      final next = _pipes.where((p) => p[0] >= 2).reduce((a, b) => a[0] < b[0] ? a : b);
      final target = next[1] + _gap / 2 + 0.5;
      if (!_started || (_y > target && _vy > -4)) _flap();
    }
    if (_started) {
      _vy += 50 * dt;
      _y += _vy * dt;
      for (final p in _pipes) {
        p[0] -= 12 * dt;
        if (p[0] < -2) {
          p[0] += _pipes.length * (_w / 2.5);
          p[1] = 1 + rng.nextInt(math.max(1, _h - _gap - 2)).toDouble();
          _score++;
        }
        if (p[0].round() >= 3 && p[0].round() <= 4 && (_y < p[1] || _y > p[1] + _gap)) _dead = true;
      }
      if (_y < 0 || _y >= _h) _dead = true;
    }
    c.clear();
    for (final p in _pipes) {
      final x = p[0].round();
      c.fillRect(x, 0, 2, p[1].round(), 0x30C030);
      c.fillRect(x, p[1].round() + _gap, 2, _h, 0x30C030);
    }
    c.set(3, _y.round(), 0xFFE000);
    c.set(4, _y.round(), 0xFF8000);
    PixelFont.tiny.draw(c, '$_score', _w - 9, 0, 0xFFFFFF);
  }
}

/// Tetris. On wide panels the well lies on its side (pieces fall to the right).
/// left/right (or up/down when sideways) move, action rotates, down drops.
class TetrisScene extends GameScene {
  @override
  String get name => 'Tetris';
  @override
  double get fps => 8;
  static const _shapes = [
    [[1, 1, 1, 1]],
    [[1, 1], [1, 1]],
    [[0, 1, 0], [1, 1, 1]],
    [[1, 0, 0], [1, 1, 1]],
    [[0, 0, 1], [1, 1, 1]],
    [[0, 1, 1], [1, 1, 0]],
    [[1, 1, 0], [0, 1, 1]],
  ];
  late int _cols, _rows; // logical well: _cols wide, pieces fall along _rows
  late bool _side;
  late List<int> _well; // 0 = empty, else colour
  List<List<int>> _p = const [];
  int _px = 0, _py = 0, _pc = 0, _score = 0;
  double _acc = 0;
  bool _dead = false;
  // auto-player plan for the current piece
  List<List<int>>? _planShape;
  int _planX = 0;

  @override
  void init(int width, int height) {
    _side = width > height;
    _cols = _side ? height : width;
    _rows = _side ? width : height;
    _reset();
  }

  void _reset() {
    _well = List.filled(_cols * _rows, 0, growable: true);
    _score = 0;
    _dead = false;
    _spawn();
  }

  void _spawn() {
    final i = rng.nextInt(_shapes.length);
    _p = [for (final r in _shapes[i]) [...r]];
    _pc = hsv(i * 51.0);
    _px = (_cols - _p[0].length) ~/ 2;
    _py = 0;
    _planShape = null;
    if (_hits(_p, _px, _py)) _dead = true;
  }

  static List<List<int>> _rot(List<List<int>> p) =>
      [for (var c = 0; c < p[0].length; c++) [for (var r = p.length - 1; r >= 0; r--) p[r][c]]];

  bool _hits(List<List<int>> p, int x, int y, [List<int>? well]) {
    well ??= _well;
    for (var r = 0; r < p.length; r++) {
      for (var c = 0; c < p[r].length; c++) {
        if (p[r][c] == 0) continue;
        final wx = x + c, wy = y + r;
        if (wx < 0 || wx >= _cols || wy >= _rows || (wy >= 0 && well[wy * _cols + wx] != 0)) return true;
      }
    }
    return false;
  }

  void _lock() {
    for (var r = 0; r < _p.length; r++) {
      for (var c = 0; c < _p[r].length; c++) {
        if (_p[r][c] != 0 && _py + r >= 0) _well[(_py + r) * _cols + _px + c] = _pc;
      }
    }
    var cleared = 0;
    for (var y = _rows - 1; y >= 0; y--) {
      if (!_well.sublist(y * _cols, (y + 1) * _cols).contains(0)) {
        _well.removeRange(y * _cols, (y + 1) * _cols);
        _well.insertAll(0, List.filled(_cols, 0));
        cleared++;
        y++;
      }
    }
    _score += [0, 10, 30, 60, 100][cleared];
    _spawn();
  }

  /// Classic heuristic: few holes, low stack, flat surface, cleared lines.
  double _evaluate(List<int> well) {
    final heights = List.filled(_cols, 0);
    var holes = 0, lines = 0;
    for (var x = 0; x < _cols; x++) {
      var seen = false;
      for (var y = 0; y < _rows; y++) {
        final filled = well[y * _cols + x] != 0;
        if (filled && !seen) {
          seen = true;
          heights[x] = _rows - y;
        } else if (!filled && seen) {
          holes++;
        }
      }
    }
    for (var y = 0; y < _rows; y++) {
      if (!well.sublist(y * _cols, (y + 1) * _cols).contains(0)) lines++;
    }
    var bump = 0;
    for (var x = 1; x < _cols; x++) {
      bump += (heights[x] - heights[x - 1]).abs();
    }
    return lines * 3.0 - holes * 2.2 - heights.fold(0, (a, b) => a + b) * 0.35 - bump * 0.25;
  }

  void _plan() {
    var best = -1e9;
    var shape = _p;
    for (var rot = 0; rot < 4; rot++) {
      for (var x = -2; x < _cols; x++) {
        if (_hits(shape, x, _py) && _hits(shape, x, 0)) continue;
        var y = _py;
        if (_hits(shape, x, y)) continue;
        while (!_hits(shape, x, y + 1)) {
          y++;
        }
        final w = List.of(_well);
        for (var r = 0; r < shape.length; r++) {
          for (var c = 0; c < shape[r].length; c++) {
            if (shape[r][c] != 0 && y + r >= 0) w[(y + r) * _cols + x + c] = 1;
          }
        }
        final v = _evaluate(w) + rng.nextDouble() * 0.01;
        if (v > best) {
          best = v;
          _planShape = shape;
          _planX = x;
        }
      }
      shape = _rot(shape);
    }
  }

  bool _sameShape(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length || a[0].length != b[0].length) return false;
    for (var r = 0; r < a.length; r++) {
      for (var c = 0; c < a[r].length; c++) {
        if (a[r][c] != b[r][c]) return false;
      }
    }
    return true;
  }

  void _autoStep() {
    _planShape ??= (() {
      _plan();
      return _planShape;
    })();
    final plan = _planShape;
    if (plan == null) return;
    if (!_sameShape(_p, plan)) {
      final r = _rot(_p);
      if (!_hits(r, _px, _py)) _p = r;
      return;
    }
    if (_px < _planX && !_hits(_p, _px + 1, _py)) {
      _px++;
    } else if (_px > _planX && !_hits(_p, _px - 1, _py)) {
      _px--;
    } else if (_px == _planX) {
      while (!_hits(_p, _px, _py + 1)) {
        _py++;
      }
      _lock();
    }
  }

  @override
  bool onInput(SceneInput input) {
    touched();
    if (_dead) {
      if (input == SceneInput.action) _reset();
      return true;
    }
    final (left, right, drop) = _side
        ? (SceneInput.up, SceneInput.down, SceneInput.right)
        : (SceneInput.left, SceneInput.right, SceneInput.down);
    if (input == left && !_hits(_p, _px - 1, _py)) _px--;
    if (input == right && !_hits(_p, _px + 1, _py)) _px++;
    if (input == drop) {
      while (!_hits(_p, _px, _py + 1)) {
        _py++;
      }
      _lock();
    }
    if (input == SceneInput.action) {
      final rot = _rot(_p);
      if (!_hits(rot, _px, _py)) _p = rot;
    }
    return true;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    tick(t);
    if (_dead) {
      _gameOver(c, _score);
      if (autoRestart(true, t)) _reset();
      return;
    }
    if (autoPilot) _autoStep();
    _acc += dt;
    if (_acc > math.max(0.15, 0.6 - _score / 500)) {
      _acc = 0;
      if (_hits(_p, _px, _py + 1)) {
        _lock();
      } else {
        _py++;
      }
    }
    c.clear();
    void plot(int wx, int wy, int col) => _side ? c.set(wy, wx, col) : c.set(wx, wy, col);
    for (var i = 0; i < _well.length; i++) {
      if (_well[i] != 0) plot(i % _cols, i ~/ _cols, _well[i]);
    }
    for (var r = 0; r < _p.length; r++) {
      for (var cc = 0; cc < _p[r].length; cc++) {
        if (_p[r][cc] != 0) plot(_px + cc, _py + r, _pc);
      }
    }
  }
}
