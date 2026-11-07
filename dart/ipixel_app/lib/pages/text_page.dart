import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../programs_store.dart';
import '../session.dart';
import 'common.dart';

/// Firmware text programs: the panel scrolls/animates them itself, even when the app is gone.
class TextPage extends StatefulWidget {
  final Session session;
  const TextPage({super.key, required this.session});
  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> with RunAction {
  final _text = TextEditingController(text: 'Hello!');
  Color _color = Colors.cyan;
  int? _gradient; // null = solid colour, else firmware preset 0..7
  int _effect = TextEffect.scrollLeft;
  int _hAlign = TextAlign.center, _vAlign = TextVAlign.middle;
  double _speed = 50;
  int? _height;
  bool _save = false;

  Session get s => widget.session;
  PanelInfo get p => s.panel;

  Future<int> _send() async {
    await s.stopLive();
    final slot = _save ? s.store.nextSlot() : 1;
    final r = await s.device.sendText(_text.text,
        color: colorToRgb(_color),
        effect: _effect,
        speed: _speed.round(),
        hAlign: _hAlign,
        vAlign: _vAlign,
        colorMode: _gradient == null ? TextColorMode.solid : TextColorMode.gradient(_gradient!),
        height: _height ?? (p.height > 32 ? 32 : p.height),
        slot: slot,
        save: _save,
        onProgress: onProgress);
    if (_save) await s.store.add(Program(slot: slot, name: _text.text, kind: 'text'));
    return r;
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        TextField(
          controller: _text,
          decoration: const InputDecoration(labelText: 'Text', border: OutlineInputBorder()),
          onSubmitted: (_) => run('Text', _send),
        ),
        const SizedBox(height: 12),
        Text('Colour', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        ColorRow(value: _gradient == null ? _color : Colors.transparent, onChanged: (c) => setState(() {
              _color = c;
              _gradient = null;
            })),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (var g = 0; g < 8; g++)
            ChoiceChip(
                label: Text('Gradient ${g + 1}'),
                selected: _gradient == g,
                onSelected: (_) => setState(() => _gradient = g)),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _effect,
          decoration: const InputDecoration(labelText: 'Animation', border: OutlineInputBorder(), isDense: true),
          items: [for (var i = 0; i < TextEffect.names.length; i++) DropdownMenuItem(value: i, child: Text(TextEffect.names[i]))],
          onChanged: (v) => setState(() => _effect = v!),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Speed'),
          Expanded(child: Slider(value: _speed, max: 100, onChanged: (v) => setState(() => _speed = v))),
        ]),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left)),
              ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center)),
              ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right)),
            ],
            selected: {_hAlign},
            onSelectionChanged: (v) => setState(() => _hAlign = v.first),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: TextVAlign.top, icon: Icon(Icons.vertical_align_top)),
              ButtonSegment(value: TextVAlign.middle, icon: Icon(Icons.vertical_align_center)),
              ButtonSegment(value: TextVAlign.bottom, icon: Icon(Icons.vertical_align_bottom)),
            ],
            selected: {_vAlign},
            onSelectionChanged: (v) => setState(() => _vAlign = v.first),
          ),
          if (p.height >= 32)
            SegmentedButton<int>(
              segments: [
                const ButtonSegment(value: 16, label: Text('16 px')),
                ButtonSegment(value: p.height > 32 ? 32 : p.height, label: Text('${p.height > 32 ? 32 : p.height} px')),
              ],
              selected: {_height ?? (p.height > 32 ? 32 : p.height)},
              onSelectionChanged: (v) => setState(() => _height = v.first),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Store on panel'),
          subtitle: Text(_save ? 'Will be saved as program slot ${s.store.nextSlot()}' : 'Show now, don\'t keep'),
          value: _save,
          onChanged: (v) => setState(() => _save = v),
        ),
        FilledButton.icon(onPressed: busy ? null : () => run('Text', _send), icon: const Icon(Icons.send), label: const Text('Send')),
        statusBar(context),
      ]);
}
