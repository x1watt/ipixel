import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'common.dart';

class ControlPage extends StatefulWidget {
  final IPixelDevice device;
  const ControlPage({super.key, required this.device});
  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with RunAction {
  double _brightness = 50;
  bool _on = true, _flipped = false, _h24 = true;

  IPixelDevice get d => widget.device;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        Text('Brightness ${_brightness.round()}%', style: Theme.of(context).textTheme.titleSmall),
        Slider(
          value: _brightness,
          max: 100,
          divisions: 20,
          onChanged: (v) => setState(() => _brightness = v),
          onChangeEnd: (v) => run('Brightness', () => d.brightness(v.round())),
        ),
        SwitchListTile(
          title: const Text('Screen on'),
          value: _on,
          onChanged: (v) {
            setState(() => _on = v);
            run('Power', () => d.power(v));
          },
        ),
        SwitchListTile(
          title: const Text('Upside down'),
          value: _flipped,
          onChanged: (v) {
            setState(() => _flipped = v);
            run('Flip', () => d.upsideDown(v));
          },
        ),
        const Divider(),
        SwitchListTile(title: const Text('24-hour clock'), value: _h24, onChanged: (v) => setState(() => _h24 = v)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var s = 1; s <= 4; s++)
            OutlinedButton(onPressed: () => run('Clock $s', () => d.clockMode(style: s, h24: _h24)), child: Text('Clock style $s')),
        ]),
        const Divider(),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Delete all stored programs?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true) run('Delete all', d.deleteAll);
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete stored programs'),
        ),
        statusBar(context),
      ]);
}
