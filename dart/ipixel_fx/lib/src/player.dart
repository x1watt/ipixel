import 'dart:async';

import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'canvas.dart';
import 'scene.dart';

/// Runs a [Scene] and streams its frames to the panel as live RGB frames.
///
/// Frames are sent back-to-back (each one waits for the panel's ack), capped at the
/// scene's fps. Identical consecutive frames are skipped, so static scenes cost nothing.
class LivePlayer {
  final IPixelDevice device;
  final void Function(PanelCanvas frame)? onFrame;
  final void Function(double fps)? onFps;
  Scene? _scene;
  PanelCanvas? canvas;
  bool _running = false;
  int _sent = 0;

  /// Time multiplier for the scene (0.25 slow … 3 fast). Changes apply immediately.
  double speed = 1;

  /// Output brightness 0.05..1, applied to every frame before it is sent.
  double brightness = 1;
  final _fpsClock = Stopwatch();

  LivePlayer(this.device, {this.onFrame, this.onFps});

  bool get running => _running;
  Scene? get scene => _scene;

  Future<void> play(Scene scene) async {
    await stop(keepMode: true);
    final p = device.panel!;
    canvas = PanelCanvas(p.width, p.height);
    scene.init(p.width, p.height);
    _scene = scene;
    if (!device.inDiy) await device.diyMode(DiyMode.enterClear);
    _running = true;
    _fpsClock
      ..reset()
      ..start();
    _sent = 0;
    unawaited(_loop(scene));
  }

  Future<void> _loop(Scene scene) async {
    final start = Stopwatch()..start();
    var last = 0.0, sceneT = 0.0;
    List<int>? prev;
    while (_running && identical(_scene, scene)) {
      final t = start.elapsedMicroseconds / 1e6;
      final dt = (t - last).clamp(0.0, 0.5) * speed;
      last = t;
      sceneT += dt;
      final c = canvas!;
      scene.draw(c, sceneT, dt);
      onFrame?.call(c);
      final bytes = c.snapshot();
      if (brightness < 0.999) {
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = (bytes[i] * brightness).round();
        }
      }
      if (prev == null || !_same(bytes, prev)) {
        try {
          await device.showRgb(bytes);
          prev = bytes;
          _sent++;
        } catch (_) {
          // missed ack: keep going, the next frame will refresh the panel
        }
      }
      if (_fpsClock.elapsedMilliseconds >= 2000) {
        onFps?.call(_sent * 1000 / _fpsClock.elapsedMilliseconds);
        _sent = 0;
        _fpsClock.reset();
      }
      final frameMs = (1000 / (scene.fps * speed.clamp(0.5, 2))).round();
      final spent = (start.elapsedMicroseconds / 1000 - t * 1000).round();
      if (frameMs > spent) await Future.delayed(Duration(milliseconds: frameMs - spent));
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void input(SceneInput i) => _scene?.onInput(i);
  void setParam(String k, Object v) => _scene?.setParam(k, v);

  Future<void> stop({bool keepMode = false}) async {
    _running = false;
    _scene = null;
    await Future.delayed(const Duration(milliseconds: 20));
    if (!keepMode && device.inDiy) {
      try {
        await device.diyMode(DiyMode.quitDiscard);
      } catch (_) {}
    }
  }
}
