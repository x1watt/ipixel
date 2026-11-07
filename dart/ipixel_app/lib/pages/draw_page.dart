import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:ipixel_fx/ipixel_fx.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../programs_store.dart';
import '../session.dart';
import 'common.dart';

enum DrawTool { pen, eraser, mirrorH, mirrorV }

/// Pixel-art editor. Every stroke is sent to the panel immediately (firmware DIY mode,
/// cmd 0x0105); the drawing can be stored on the panel as a program.
class DrawPage extends StatefulWidget {
  final Session session;
  final bool active;
  const DrawPage({super.key, required this.session, required this.active});
  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> with RunAction {
  late final PanelCanvas _c;
  Color _color = Colors.red;
  DrawTool _tool = DrawTool.pen;
  bool _live = false;
  final _pending = <(int, int)>[];
  Timer? _flush;
  int? _lastX, _lastY;

  Session get s => widget.session;
  PanelInfo get p => s.panel;

  @override
  void initState() {
    super.initState();
    _c = PanelCanvas(p.width, p.height);
  }

  @override
  void didUpdateWidget(DrawPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && _live) _leave();
  }

  @override
  void dispose() {
    _flush?.cancel();
    if (_live) s.device.diyMode(DiyMode.quitDiscard).catchError((_) => false);
    super.dispose();
  }

  Future<void> _enter() async {
    await s.stopLive();
    await s.device.diyMode(DiyMode.enterClear);
    // push the current canvas so the panel matches what is on screen
    await s.device.showRgb(_c.snapshot());
    setState(() => _live = true);
  }

  Future<void> _leave() async {
    try {
      await s.device.diyMode(DiyMode.quitKeep);
    } catch (_) {}
    if (mounted) setState(() => _live = false);
  }

  int get _rgbInt => colorToInt(_color);

  void _paint(int x, int y) {
    if (!_c.inside(x, y)) return;
    if (x == _lastX && y == _lastY) return;
    _lastX = x;
    _lastY = y;
    final pts = <(int, int)>[(x, y)];
    if (_tool == DrawTool.mirrorH) pts.add((p.width - 1 - x, y));
    if (_tool == DrawTool.mirrorV) pts.add((x, p.height - 1 - y));
    final col = _tool == DrawTool.eraser ? 0 : _rgbInt;
    for (final (px, py) in pts) {
      _c.set(px, py, col);
    }
    setState(() {});
    if (_live) {
      _pending.addAll(pts);
      _flush ??= Timer(const Duration(milliseconds: 60), _send);
    }
  }

  Future<void> _send() async {
    _flush = null;
    final pts = List.of(_pending);
    _pending.clear();
    if (pts.isEmpty) return;
    final rgb = _tool == DrawTool.eraser ? [0, 0, 0] : colorToRgb(_color);
    final moveType = _tool == DrawTool.eraser ? 4 : 0;
    for (var i = 0; i < pts.length; i += 120) {
      await s.device.diyDraw(rgb, pts.sublist(i, i + 120 > pts.length ? pts.length : i + 120), moveType: moveType);
    }
  }

  Future<void> _clear() async {
    _c.clear();
    setState(() {});
    if (_live) await s.device.showRgb(_c.snapshot());
  }

  Future<void> _store() async {
    final gif = img.encodeGif(_c.toImage());
    final slot = s.store.nextSlot();
    await run('Store in slot $slot', () async {
      await _leave();
      final r = await s.device.uploadGif(gif, slot: slot, save: true, onProgress: onProgress);
      await s.store.add(Program(slot: slot, name: 'Drawing', kind: 'draw'));
      return r;
    });
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        LayoutBuilder(builder: (_, cons) {
          final cell = (cons.maxWidth / p.width).floorToDouble().clamp(3, 40).toDouble();
          final w = cell * p.width, h = cell * p.height;
          void at(Offset o) => _paint((o.dx / cell).floor(), (o.dy / cell).floor());
          return Center(
            child: GestureDetector(
              onPanStart: (d) {
                _lastX = null;
                at(d.localPosition);
              },
              onPanUpdate: (d) => at(d.localPosition),
              onTapDown: (d) {
                _lastX = null;
                at(d.localPosition);
              },
              child: CustomPaint(size: Size(w, h), painter: _GridPainter(_c, cell)),
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(children: [
          if (!_live)
            FilledButton.icon(onPressed: () => run('Live drawing', _enter), icon: const Icon(Icons.brush), label: const Text('Draw live on panel'))
          else
            FilledButton.tonalIcon(onPressed: _leave, icon: const Icon(Icons.stop), label: const Text('Stop live')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _clear, icon: const Icon(Icons.layers_clear), label: const Text('Clear')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: busy ? null : _store, icon: const Icon(Icons.save), label: const Text('Store on panel')),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<DrawTool>(
          segments: const [
            ButtonSegment(value: DrawTool.pen, icon: Icon(Icons.edit), label: Text('Pen')),
            ButtonSegment(value: DrawTool.eraser, icon: Icon(Icons.cleaning_services), label: Text('Eraser')),
            ButtonSegment(value: DrawTool.mirrorH, icon: Icon(Icons.flip), label: Text('Mirror ↔')),
            ButtonSegment(value: DrawTool.mirrorV, icon: Icon(Icons.flip_camera_android), label: Text('Mirror ↕')),
          ],
          selected: {_tool},
          onSelectionChanged: (v) => setState(() => _tool = v.first),
        ),
        const SizedBox(height: 12),
        ColorRow(value: _color, onChanged: (c) => setState(() => _color = c)),
        statusBar(context),
      ]);
}

class _GridPainter extends CustomPainter {
  final PanelCanvas c;
  final double cell;
  _GridPainter(this.c, this.cell);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101010));
    final paint = Paint();
    for (var y = 0; y < c.height; y++) {
      for (var x = 0; x < c.width; x++) {
        final v = c.get(x, y);
        paint.color = v == 0 ? const Color(0xFF202020) : Color(0xFF000000 | v);
        canvas.drawRect(Rect.fromLTWH(x * cell + 0.5, y * cell + 0.5, cell - 1, cell - 1), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
