import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../session.dart';
import 'common.dart';

/// Firmware features that don't need streaming: clock faces, countdown, stopwatch,
/// scoreboard, riding signs, schedules, alarms, password and panel settings.
class ToolsPage extends StatefulWidget {
  final Session session;
  const ToolsPage({super.key, required this.session});
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> with RunAction {
  bool _h24 = true, _date = false;
  int _cdMin = 5, _cdSec = 0;
  int _s1 = 0, _s2 = 0;
  double _brightness = 50;
  bool _on = true, _flipped = false;
  final _schedules = <_Sched>[];
  final _pwd = TextEditingController();
  int _alarmHour = 7, _alarmMin = 30;
  List<bool> _alarmDays = List.filled(7, true);

  Session get s => widget.session;
  IPixelDevice get d => s.device;

  String _opt(bool? r) => r == null ? 'sent (this panel sends no ack for it)' : r ? 'ok ✓' : 'rejected';

  Future<void> _prep() => s.stopLive();

  @override
  Widget build(BuildContext context) {
    const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    Widget dayPicker(List<bool> v, void Function(List<bool>) set) => Wrap(spacing: 4, children: [
          for (var i = 0; i < 7; i++)
            FilterChip(label: Text(days[i]), selected: v[i], visualDensity: VisualDensity.compact, onSelected: (b) {
              final n = List.of(v);
              n[i] = b;
              set(n);
            }),
        ]);
    return PageBody(children: [
      statusBar(context),
      ExpansionTile(title: const Text('Clock faces'), initiallyExpanded: true, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var st = 1; st <= 10; st++)
            OutlinedButton(onPressed: () => run('Clock $st', () async {
                  await _prep();
                  return d.clockMode(style: st, h24: _h24, showDate: _date);
                }), child: Text('Face $st')),
        ]),
        Row(children: [
          Expanded(child: SwitchListTile(title: const Text('24 h'), value: _h24, onChanged: (v) => setState(() => _h24 = v))),
          Expanded(child: SwitchListTile(title: const Text('Date'), value: _date, onChanged: (v) => setState(() => _date = v))),
        ]),
      ]),
      ExpansionTile(title: const Text('Countdown'), children: [
        Row(children: [
          const Text('Minutes'),
          Expanded(child: Slider(value: _cdMin.toDouble(), max: 99, divisions: 99, label: '$_cdMin', onChanged: (v) => setState(() => _cdMin = v.round()))),
          const Text('Seconds'),
          Expanded(child: Slider(value: _cdSec.toDouble(), max: 59, divisions: 59, label: '$_cdSec', onChanged: (v) => setState(() => _cdSec = v.round()))),
        ]),
        Wrap(spacing: 8, children: [
          for (final (label, flag) in [('Start', 1), ('Pause', 2), ('Resume', 3), ('Reset', 0)])
            OutlinedButton(onPressed: () => run('Countdown $label', () async {
                  await _prep();
                  return _opt(await d.countdown(flag, flag == 0 ? 0 : _cdMin, flag == 0 ? 0 : _cdSec));
                }), child: Text(label)),
        ]),
      ]),
      ExpansionTile(title: const Text('Stopwatch'), children: [
        Wrap(spacing: 8, children: [
          for (final (label, flag) in [('Start', 1), ('Pause', 2), ('Resume', 3), ('Reset', 0)])
            OutlinedButton(onPressed: () => run('Stopwatch $label', () async {
                  await _prep();
                  return _opt(await d.stopwatch(flag));
                }), child: Text(label)),
        ]),
      ]),
      ExpansionTile(title: const Text('Scoreboard'), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _counter('Home', _s1, (v) => setState(() => _s1 = v)),
          const SizedBox(width: 24),
          _counter('Away', _s2, (v) => setState(() => _s2 = v)),
        ]),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: () => run('Scoreboard', () async {
                await _prep();
                return _opt(await d.scoreboard(_s1, _s2));
              }), child: const Text('Show')),
          OutlinedButton(onPressed: () {
            setState(() => _s1 = _s2 = 0);
            run('Scoreboard reset', () async => _opt(await d.scoreboard(0, 0)));
          }, child: const Text('Reset')),
        ]),
      ]),
      ExpansionTile(title: const Text('Riding / bike signs'), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, mode) in [('← Left', 0), ('Right →', 1), ('Go', 2), ('Stop', 3), ('SOS', 4), ('Flash', 5)])
            OutlinedButton(onPressed: () => run('Sign $label', () async {
                  await _prep();
                  return _opt(await d.sport(mode));
                }), child: Text(label)),
        ]),
      ]),
      ExpansionTile(title: const Text('Scheduled on/off'), children: [
        for (var i = 0; i < _schedules.length; i++)
          ListTile(
            dense: true,
            title: Text('${_schedules[i].on ? 'ON' : 'OFF'} at ${_schedules[i].hour.toString().padLeft(2, '0')}:${_schedules[i].minute.toString().padLeft(2, '0')}'),
            subtitle: dayPicker(_schedules[i].days, (v) => setState(() => _schedules[i].days = v)),
            trailing: Wrap(children: [
              IconButton(icon: const Icon(Icons.send), onPressed: () => run('Schedule ${i + 1}', () async {
                    final e = _schedules[i];
                    return d.schedule(index: i, on: e.on, hour: e.hour, minute: e.minute, days: e.days);
                  })),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => run('Disable schedule ${i + 1}', () async {
                    final e = _schedules[i];
                    final r = await d.schedule(index: i, on: e.on, hour: e.hour, minute: e.minute, days: e.days, enabled: false);
                    setState(() => _schedules.removeAt(i));
                    return r;
                  })),
            ]),
          ),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: _schedules.length >= 10 ? null : () => _addSchedule(true), icon: const Icon(Icons.add), label: const Text('Turn on at…')),
          OutlinedButton.icon(onPressed: _schedules.length >= 10 ? null : () => _addSchedule(false), icon: const Icon(Icons.add), label: const Text('Turn off at…')),
        ]),
        const Padding(padding: EdgeInsets.all(8), child: Text('Each entry is sent to the panel with "send". The panel keeps them; the app does not list what is already stored.', style: TextStyle(fontSize: 12))),
      ]),
      ExpansionTile(title: const Text('Alarm with picture'), children: [
        ListTile(
          title: Text('${_alarmHour.toString().padLeft(2, '0')}:${_alarmMin.toString().padLeft(2, '0')}'),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _alarmHour, minute: _alarmMin));
            if (t != null) {
              setState(() {
                _alarmHour = t.hour;
                _alarmMin = t.minute;
              });
            }
          },
        ),
        dayPicker(_alarmDays, (v) => setState(() => _alarmDays = v)),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: busy ? null : () async {
              final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
              final b = r?.files.single.bytes;
              if (b == null) return;
              final src = decodeAny(b);
              if (src == null) return;
              final gif = gifForPanel(src, s.panel.width, s.panel.height);
              await run('Alarm', () async {
                await _prep();
                return d.uploadAlarm(index: 0, hour: _alarmHour, minute: _alarmMin, days: _alarmDays, image: gif, onProgress: onProgress);
              });
            },
            icon: const Icon(Icons.alarm_add),
            label: const Text('Pick picture and set alarm 1')),
        OutlinedButton(onPressed: () => run('Alarm off', () async {
              await _prep();
              final blank = img.encodeGif(img.Image(width: s.panel.width, height: s.panel.height));
              return d.uploadAlarm(index: 0, hour: _alarmHour, minute: _alarmMin, days: _alarmDays, image: blank, enabled: false);
            }), child: const Text('Disable alarm 1')),
      ]),
      ExpansionTile(title: const Text('Panel'), children: [
        Text('Brightness ${_brightness.round()}%'),
        Slider(value: _brightness, max: 100, divisions: 20, onChanged: (v) => setState(() => _brightness = v), onChangeEnd: (v) => run('Brightness', () => d.brightness(v.round()))),
        SwitchListTile(title: const Text('Screen on'), value: _on, onChanged: (v) {
          setState(() => _on = v);
          run('Power', () => d.power(v));
        }),
        SwitchListTile(title: const Text('Upside down'), value: _flipped, onChanged: (v) {
          setState(() => _flipped = v);
          run('Flip', () => d.upsideDown(v));
        }),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('${s.panel.width}×${s.panel.height}, type code 0x${s.panel.code.toRadixString(16)}, frame ${s.panel.frameSize} B'),
          subtitle: Text(s.name),
        ),
      ]),
      ExpansionTile(title: const Text('Password lock'), children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Careful: a forgotten password locks the panel for every app. 6 digits (4 on some models).', style: TextStyle(fontSize: 12))),
        TextField(controller: _pwd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Digits', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: () => run('Verify', () => d.verifyPassword(_pwd.text)), child: const Text('Verify')),
          OutlinedButton(onPressed: () => _confirm('Set password ${_pwd.text}?', () => run('Set password', () => d.setPassword(true, _pwd.text))), child: const Text('Set')),
          OutlinedButton(onPressed: () => _confirm('Remove the password?', () => run('Remove password', () => d.setPassword(false, _pwd.text))), child: const Text('Remove')),
        ]),
      ]),
      const SizedBox(height: 24),
    ]);
  }

  Widget _counter(String label, int v, void Function(int) set) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => set((v - 1).clamp(0, 999)), icon: const Icon(Icons.remove)),
          Text('$v', style: Theme.of(context).textTheme.headlineMedium),
          IconButton(onPressed: () => set((v + 1).clamp(0, 999)), icon: const Icon(Icons.add)),
        ]),
      ]);

  Future<void> _addSchedule(bool on) async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() => _schedules.add(_Sched(on, t.hour, t.minute)));
  }

  Future<void> _confirm(String q, VoidCallback yes) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(title: Text(q), actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
            ]));
    if (ok == true) yes();
  }
}

class _Sched {
  bool on;
  int hour, minute;
  List<bool> days = List.filled(7, true);
  _Sched(this.on, this.hour, this.minute);
}
