import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../viewfinder/capture.dart';
import '../viewfinder/locate.dart';
import 'common.dart';
import 'pixels.dart';

/// See-through viewfinder: the framed area of this window is transparent; whatever is
/// visible through it (other apps, the desktop) is streamed to the LED once per second.
///
/// Move/resize the app window to choose the content. The magenta frame is also how the
/// app finds its own position in the shared screen (Wayland gives apps no global coordinates).
class ViewfinderPage extends StatefulWidget {
  final IPixelDevice device;
  final bool active;
  const ViewfinderPage({super.key, required this.device, required this.active});
  @override
  State<ViewfinderPage> createState() => _ViewfinderPageState();
}

class _ViewfinderPageState extends State<ViewfinderPage> {
  ScreenCapture? _cap;
  StreamSubscription? _sub;
  bool _starting = false, _sending = false;
  Uint8List? _last;
  ui.Image? _sent;
  String _status = '';
  int _zoom = 1; // screen pixels per LED (per axis)

  IPixelDevice get d => widget.device;
  PanelInfo get p => d.panel!;

  @override
  void didUpdateWidget(ViewfinderPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && _cap != null) _stop();
  }

  @override
  void dispose() {
    _stop(silent: true);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _status = 'Pick the monitor this window is on, in the system dialog…';
    });
    try {
      await d.diyMode(DiyMode.enterClear);
      final cap = await ScreenCapture.start(fps: 1);
      _cap = cap;
      _sub = cap.frames.listen(_onFrame);
      setState(() => _status = 'Live – keep the magenta frame on the shared monitor');
    } catch (e) {
      await _stop(silent: true);
      setState(() => _status = 'Could not start: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop({bool silent = false}) async {
    await _sub?.cancel();
    _sub = null;
    final cap = _cap;
    _cap = null;
    await cap?.stop();
    if (d.inDiy) {
      try {
        await d.diyMode(DiyMode.quitDiscard);
      } catch (_) {}
    }
    if (!silent && mounted) setState(() => _status = 'Stopped');
  }

  Future<void> _onFrame(ScreenFrame f) async {
    if (_sending) return; // panel still busy: skip this frame
    final hole = locateViewfinder(f.rgb, f.width, f.height);
    if (hole == null) {
      if (mounted) setState(() => _status = 'Frame not found – is this window on the shared monitor and not covered?');
      return;
    }
    final rgb = cropExact(f.rgb, f.width, hole, p.width, p.height, zoom: _zoom);
    if (_last != null && _same(rgb, _last!)) return;
    _sending = true;
    try {
      await d.showRgb(rgb);
      _last = rgb;
      ui.decodeImageFromPixels(rgbToRgba(rgb, p.width, p.height), p.width, p.height, ui.PixelFormat.rgba8888,
          (i) => mounted ? setState(() => _sent = i) : null);
      if (mounted) setState(() => _status = 'Live · area $hole');
    } catch (e) {
      if (mounted) setState(() => _status = 'Send failed: $e');
    } finally {
      _sending = false;
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final live = _cap != null;
    if (!ScreenCapture.supported) {
      return const PageBody(children: [
        Text('The see-through viewfinder currently needs a Linux Wayland session '
            '(GNOME/KDE with PipeWire + GStreamer).'),
      ]);
    }
    return Column(children: [
      // opaque control strip
      ColoredBox(
        color: surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            if (!live)
              FilledButton.icon(
                  onPressed: _starting ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('Go live'))
            else
              FilledButton.tonalIcon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop')),
            const SizedBox(width: 16),
            Expanded(child: Text(_status.isEmpty
                ? 'Move/resize this window so the frame covers what you want on the LED'
                : _status, maxLines: 2, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1:1')),
                ButtonSegment(value: 2, label: Text('2×')),
                ButtonSegment(value: 3, label: Text('3×')),
              ],
              selected: {_zoom},
              onSelectionChanged: (v) => setState(() {
                _zoom = v.first;
                _last = null;
              }),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 128, child: PixelPreview(image: _sent, aspect: p.width / p.height)),
          ]),
        ),
      ),
      // transparent hole with magenta frame, surrounded by opaque surface
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          // Hole = exactly (panel x zoom) physical pixels, snapped to the physical pixel grid.
          final dpr = MediaQuery.devicePixelRatioOf(context);
          // +2 spare physical px per side; only the exact centre (panel x zoom) is sent
          final pw = (p.width * _zoom + 4).toDouble(), ph = (p.height * _zoom + 4).toDouble();
          double snap(double logical) => (logical * dpr).roundToDouble() / dpr;
          final w = pw / dpr, h = ph / dpr;
          final rect = Rect.fromLTWH(snap((c.maxWidth - w) / 2), snap((c.maxHeight - h) / 2), w, h);
          return CustomPaint(size: Size(c.maxWidth, c.maxHeight), painter: _HolePainter(rect, surface, dpr));
        }),
      ),
    ]);
  }
}

class _HolePainter extends CustomPainter {
  final Rect hole;
  final Color surface;
  static const borderPx = 4.0; // physical pixels
  final double dpr;
  _HolePainter(this.hole, this.surface, this.dpr);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = hole.inflate(borderPx / dpr);
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(frame),
        Paint()
          ..color = surface
          ..isAntiAlias = false);
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(frame)
          ..addRect(hole),
        Paint()
          ..color = const Color.fromARGB(255, markerR, markerG, markerB)
          ..isAntiAlias = false);
    // the hole itself is left unpainted -> fully transparent window pixels
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.surface != surface || old.dpr != dpr;
}
