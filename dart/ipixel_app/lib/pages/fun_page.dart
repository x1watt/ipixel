import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ipixel_fx/ipixel_fx.dart';

import '../session.dart';
import 'common.dart';
import 'pixels.dart';

/// Launcher for the live effects engine: clocks, effects, signs, widgets and games.
/// The app renders every frame and streams it; nothing here needs firmware support.
class FunPage extends StatefulWidget {
  final Session session;
  final bool active;
  const FunPage({super.key, required this.session, this.active = true});
  @override
  State<FunPage> createState() => _FunPageState();
}

class _FunPageState extends State<FunPage> {
  String _group = sceneGroups.first;
  SceneEntry? _current;
  ui.Image? _preview;
  Color _color = Colors.amber;
  String _text = 'HELLO';
  String _style = 'rainbow';
  bool _auto = false;
  final _textCtrl = TextEditingController(text: 'HELLO');
  Timer? _fpsTimer;
  double _speed = 1, _brightness = 1;
  bool _previewBusy = false;

  Session get s => widget.session;
  LivePlayer get player => s.player;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    s.frameListeners.add(_onFrame);
    _fpsTimer = Timer.periodic(const Duration(seconds: 2), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    s.frameListeners.remove(_onFrame);
    _fpsTimer?.cancel();
    super.dispose();
  }

  void _onFrame(PanelCanvas c) {
    if (_previewBusy || !mounted) return;
    _previewBusy = true;
    ui.decodeImageFromPixels(rgbToRgba(c.rgbBytes, c.width, c.height), c.width, c.height, ui.PixelFormat.rgba8888, (im) {
      _previewBusy = false;
      if (mounted) setState(() => _preview = im);
    });
  }

  Future<void> _play(SceneEntry e) async {
    await s.mic.stop();
    final scene = e.create();
    _applyParams(scene);
    await player.play(scene);
    setState(() => _current = e);
  }

  void _applyParams(Scene scene) {
    scene.setParam('color', colorToInt(_color));
    scene.setParam('text', _text);
    scene.setParam('style', _style);
    scene.setParam('auto', _auto);
  }

  Future<void> _stop() async {
    await player.stop();
    setState(() {
      _current = null;
      _preview = null;
    });
  }

  /// Global handler: arrows reach the game even when a chip, slider or the list has focus.
  bool _onKey(KeyEvent e) {
    if (!(_current?.interactive ?? false) || !widget.active) return false;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final i = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => SceneInput.up,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => SceneInput.down,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => SceneInput.left,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => SceneInput.right,
      LogicalKeyboardKey.space || LogicalKeyboardKey.enter => SceneInput.action,
      LogicalKeyboardKey.escape || LogicalKeyboardKey.backspace => SceneInput.back,
      _ => null,
    };
    if (i == null) return false;
    player.input(i);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = s.panel;
    final entries = sceneCatalog.where((e) => e.group == _group).toList();
    final usesText = _current != null && (_current!.group == 'Text' || _current!.name == 'Progress bar');
    return PageBody(children: [
        PixelPreview(image: _preview, aspect: p.width / p.height),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text(_current == null ? 'Pick something below' : '${_current!.name} · ${s.fps.toStringAsFixed(1)} fps',
                  style: Theme.of(context).textTheme.titleSmall)),
          if (_current != null) FilledButton.tonalIcon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop')),
        ]),
        if (_current?.interactive ?? false) ...[
          const SizedBox(height: 8),
          Center(child: _DPad(onInput: player.input)),
          Center(
            child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilterChip(
                label: const Text('Auto-play'),
                selected: _auto,
                onSelected: (v) {
                  setState(() => _auto = v);
                  player.setParam('auto', v);
                },
              ),
              const Text('Keys: arrows / WASD, space = action, esc = reset · idle 3 s = auto-play', style: TextStyle(fontSize: 11)),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        if (_current != null) ...[
          Row(children: [
            const Icon(Icons.speed, size: 18),
            Expanded(
              child: Slider(
                value: _speed, min: 0.25, max: 3, divisions: 11, label: '${_speed.toStringAsFixed(2)}×',
                onChanged: (v) => setState(() => player.speed = _speed = v),
              ),
            ),
            const Icon(Icons.brightness_6, size: 18),
            Expanded(
              child: Slider(
                value: _brightness, min: 0.05, max: 1, divisions: 19, label: '${(_brightness * 100).round()}%',
                onChanged: (v) => setState(() => player.brightness = _brightness = v),
              ),
            ),
          ]),
          ColorRow(
              value: _color,
              onChanged: (c) {
                setState(() => _color = c);
                player.setParam('color', colorToInt(c));
              }),
          if (usesText) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(labelText: 'Text', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) {
                _text = v;
                player.setParam('text', v);
              },
            ),
          ],
          if (_current!.name == 'Text effects') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final st in TextFxScene.styles)
                ChoiceChip(
                    label: Text(st),
                    selected: _style == st,
                    onSelected: (_) {
                      setState(() => _style = st);
                      player.setParam('style', st);
                    }),
            ]),
          ],
        ],
        const Divider(height: 24),
        Wrap(spacing: 6, children: [
          for (final g in sceneGroups) ChoiceChip(label: Text(g), selected: _group == g, onSelected: (_) => setState(() => _group = g)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in entries)
            ActionChip(
              avatar: Icon(e.interactive ? Icons.sports_esports : Icons.play_arrow, size: 16),
              label: Text(e.name),
              backgroundColor: _current == e ? Theme.of(context).colorScheme.primaryContainer : null,
              onPressed: () => _play(e),
            ),
        ]),
      ]);
  }
}

class _DPad extends StatelessWidget {
  final void Function(SceneInput) onInput;
  const _DPad({required this.onInput});
  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, SceneInput inp) => IconButton.filledTonal(
        iconSize: 28, onPressed: () => onInput(inp), icon: Icon(i), padding: const EdgeInsets.all(12));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Column(mainAxisSize: MainAxisSize.min, children: [
        b(Icons.keyboard_arrow_up, SceneInput.up),
        Row(mainAxisSize: MainAxisSize.min, children: [
          b(Icons.keyboard_arrow_left, SceneInput.left),
          const SizedBox(width: 52),
          b(Icons.keyboard_arrow_right, SceneInput.right),
        ]),
        b(Icons.keyboard_arrow_down, SceneInput.down),
      ]),
      const SizedBox(width: 32),
      Column(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filled(iconSize: 32, padding: const EdgeInsets.all(16), onPressed: () => onInput(SceneInput.action), icon: const Icon(Icons.circle_outlined)),
        const Text('action', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        IconButton.outlined(onPressed: () => onInput(SceneInput.back), icon: const Icon(Icons.refresh)),
      ]),
    ]);
  }
}
