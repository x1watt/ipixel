import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'portal.dart';

class ScreenFrame {
  final int width, height;
  final Uint8List rgb;
  const ScreenFrame(this.width, this.height, this.rgb);
}

/// Monitor capture at [fps] (default 1/s): portal + GStreamer `pipewiresrc` on Wayland.
class ScreenCapture {
  final Process _proc;
  final PortalScreenCast _cast;
  final int width, height;
  final _ctrl = StreamController<ScreenFrame>.broadcast();

  ScreenCapture._(this._proc, this._cast, this.width, this.height) {
    final fb = width * height * 3;
    final buf = BytesBuilder(copy: false);
    _proc.stdout.listen((chunk) {
      buf.add(chunk);
      if (buf.length >= fb) {
        final all = buf.takeBytes();
        final n = all.length ~/ fb;
        _ctrl.add(ScreenFrame(width, height, Uint8List.sublistView(all, (n - 1) * fb, n * fb)));
        if (all.length > n * fb) buf.add(Uint8List.sublistView(all, n * fb));
      }
    }, onDone: () => _ctrl.close());
    _proc.stderr.drain<void>();
  }

  Stream<ScreenFrame> get frames => _ctrl.stream;

  static bool get supported =>
      Platform.isLinux && (Platform.environment['XDG_SESSION_TYPE'] ?? '') == 'wayland';

  static Future<ScreenCapture> start({int fps = 1}) async {
    final cast = await PortalScreenCast.open();
    try {
      // Probe the stream's native (physical) size so frames are captured 1:1, never rescaled.
      final (w, h) = await _probeSize(cast.nodeId) ?? cast.size ?? (1920, 1080);
      final pipeline = 'pipewiresrc path=${cast.nodeId} do-timestamp=true keepalive-time=1000 ! '
          'videoconvert ! videorate drop-only=true ! '
          'video/x-raw,format=RGB,width=$w,height=$h,framerate=$fps/1 ! fdsink fd=1 sync=false';
      final p = await Process.start('gst-launch-1.0', ['-q', ...pipeline.split(' ')]);
      return ScreenCapture._(p, cast, w, h);
    } catch (e) {
      await cast.close();
      if (e is ProcessException) {
        throw StateError('gst-launch-1.0 not found (install gstreamer1.0-tools + gstreamer1.0-pipewire)');
      }
      rethrow;
    }
  }

  static Future<(int, int)?> _probeSize(int node) async {
    try {
      final r = await Process.run('gst-launch-1.0',
              ['-v', 'pipewiresrc', 'path=$node', 'num-buffers=1', '!', 'videoconvert', '!', 'fakesink'])
          .timeout(const Duration(seconds: 8));
      final m = RegExp(r'width=\(int\)(\d+), height=\(int\)(\d+)').firstMatch('${r.stdout}');
      return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    _proc.kill();
    await _cast.close();
  }
}
