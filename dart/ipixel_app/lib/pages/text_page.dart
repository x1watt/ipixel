import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'common.dart';

class TextPage extends StatefulWidget {
  final IPixelDevice device;
  const TextPage({super.key, required this.device});
  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> with RunAction {
  final _text = TextEditingController(text: 'Hello!');
  Color _color = Colors.cyan;
  int _effect = TextEffect.scrollLeft;
  double _speed = 50;
  bool _save = false;

  IPixelDevice get d => widget.device;

  Future<int> _send() async {
    final p = d.panel!;
    final h = p.height > 32 ? 32 : p.height;
    // Pure-Dart bitmap font (package:image). Flutter's offscreen text raster is unreliable on Linux.
    return d.sendText(_text.text,
        color: colorToRgb(_color), effect: _effect, speed: _speed.round(), height: h,
        save: _save, onProgress: onProgress);
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        TextField(
          controller: _text,
          decoration: const InputDecoration(labelText: 'Text', border: OutlineInputBorder()),
          onSubmitted: (_) => run('Text', _send),
        ),
        const SizedBox(height: 16),
        ColorRow(value: _color, onChanged: (c) => setState(() => _color = c)),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: TextEffect.fixed, label: Text('Static')),
            ButtonSegment(value: TextEffect.scrollLeft, label: Text('Scroll ←')),
            ButtonSegment(value: TextEffect.scrollRight, label: Text('Scroll →')),
          ],
          selected: {_effect},
          onSelectionChanged: (s) => setState(() => _effect = s.first),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Speed'),
          Expanded(child: Slider(value: _speed, max: 100, onChanged: (v) => setState(() => _speed = v))),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Store on display'),
          subtitle: const Text('Off: show now without saving to a program slot'),
          value: _save,
          onChanged: (v) => setState(() => _save = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: busy ? null : () => run('Text', _send), icon: const Icon(Icons.send), label: const Text('Send')),
        statusBar(context),
      ]);
}
