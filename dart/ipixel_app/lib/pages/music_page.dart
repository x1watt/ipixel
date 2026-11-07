import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ipixel_fx/ipixel_fx.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../mic.dart';
import '../session.dart';
import 'common.dart';

/// Microphone-driven visualizer. "Panel" styles use the firmware's own rhythm renderer
/// (cmd 0x0201/0x0200, like the official app); "App" styles render here and stream.
class MusicPage extends StatefulWidget {
  final Session session;
  final bool active;
  const MusicPage({super.key, required this.session, required this.active});
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  int _style = 0; // 0..4 firmware spectrum, 5..6 firmware level, 7 app meter
  StreamSubscription? _sub;
  MicFrame _last = const MicFrame(0, []);
  String _status = '';
  double _gain = 1.5;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  Session get s => widget.session;
  bool get _running => _sub != null;

  @override
  void didUpdateWidget(MusicPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && _running) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    await s.stopLive();
    try {
      if (_style == 7) {
        await s.player.play(VuMeterScene());
      } else if (s.device.inDiy) {
        await s.device.diyMode(DiyMode.quitDiscard);
      }
      await s.mic.start();
      _sub = s.mic.frames.listen(_onMic);
      setState(() => _status = 'Listening…');
    } catch (e) {
      setState(() => _status = 'Could not start: $e');
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await s.mic.stop();
    await s.player.stop();
    if (mounted) setState(() => _status = 'Stopped');
  }

  void _onMic(MicFrame f) {
    if (!mounted) return;
    setState(() => _last = f);
    final now = DateTime.now();
    if (now.difference(_lastSend).inMilliseconds < 100) return; // the official app also sends at ≤10 Hz
    _lastSend = now;
    final bands = f.bands.map((b) => (b * _gain).clamp(0.0, 1.0)).toList();
    if (_style == 7) {
      s.player.setParam('spectrum', bands);
      s.player.setParam('level', (f.level * _gain).clamp(0.0, 1.0));
    } else if (_style <= 4) {
      s.device.rhythmBars(_style, bands.map((b) => (b * 15).round()).toList());
    } else {
      s.device.rhythmLevel(((f.level * _gain).clamp(0.0, 1.0) * 7).round(), _style - 5);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        SizedBox(
          height: 80,
          child: CustomPaint(size: Size.infinite, painter: _BarsPainter(_last.bands, _last.level, _gain)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (!_running)
            FilledButton.icon(onPressed: _start, icon: const Icon(Icons.mic), label: const Text('Start'))
          else
            FilledButton.tonalIcon(onPressed: _stop, icon: const Icon(Icons.mic_off), label: const Text('Stop')),
          const SizedBox(width: 12),
          Expanded(child: Text(_status)),
        ]),
        const SizedBox(height: 12),
        Text('Style', style: Theme.of(context).textTheme.labelMedium),
        Wrap(spacing: 6, children: [
          for (var i = 0; i < 5; i++) ChoiceChip(label: Text('Panel spectrum ${i + 1}'), selected: _style == i, onSelected: (_) => _set(i)),
          for (var i = 5; i < 7; i++) ChoiceChip(label: Text('Panel level ${i - 4}'), selected: _style == i, onSelected: (_) => _set(i)),
          ChoiceChip(label: const Text('App meter'), selected: _style == 7, onSelected: (_) => _set(7)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Gain'),
          Expanded(child: Slider(value: _gain, min: 0.5, max: 4, onChanged: (v) => setState(() => _gain = v))),
        ]),
        const Text('Panel styles are drawn by the display firmware (as in the official app). '
            'Linux needs parecord (pulseaudio-utils).', style: TextStyle(fontSize: 12)),
      ]);

  Future<void> _set(int i) async {
    final was = _running;
    if (was) await _stop();
    setState(() => _style = i);
    if (was) await _start();
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> bands;
  final double level, gain;
  _BarsPainter(this.bands, this.level, this.gain);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (bands.isEmpty) return;
    final bw = size.width / bands.length;
    for (var i = 0; i < bands.length; i++) {
      final h = (bands[i] * gain).clamp(0.0, 1.0) * size.height;
      canvas.drawRect(Rect.fromLTWH(i * bw + 1, size.height - h, bw - 2, h),
          Paint()..color = HSVColor.fromAHSV(1, 120 - 120 * bands[i], 1, 1).toColor());
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * (level * gain).clamp(0, 1), 3), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}
