import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import '../programs_store.dart';
import '../session.dart';
import 'common.dart';
import 'pixels.dart';

/// Pictures and animated GIFs, rescaled to the panel and played by the firmware.
class MediaPage extends StatefulWidget {
  final Session session;
  const MediaPage({super.key, required this.session});
  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> with RunAction {
  String? _name;
  Uint8List? _gif;
  ui.Image? _preview;
  bool _save = false;

  Session get s => widget.session;
  PanelInfo get p => s.panel;

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final src = decodeAny(f!.bytes!);
    if (src == null) {
      setState(() => status = 'Unsupported image');
      return;
    }
    final gif = gifForPanel(src, p.width, p.height);
    final first = imageToRgb(src, p.width, p.height);
    ui.decodeImageFromPixels(rgbToRgba(first, p.width, p.height), p.width, p.height, ui.PixelFormat.rgba8888,
        (im) => setState(() => _preview = im));
    setState(() {
      _name = '${f.name} (${src.frames.length} frame${src.frames.length == 1 ? '' : 's'}, ${gif.length ~/ 1024} KB)';
      _gif = gif;
    });
  }

  Future<int> _send() async {
    await s.stopLive();
    final slot = _save ? s.store.nextSlot() : 1;
    final r = await s.device.uploadGif(_gif!, slot: slot, save: _save, onProgress: onProgress);
    if (_save) await s.store.add(Program(slot: slot, name: _name!.split(' (').first, kind: 'gif'));
    return r;
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text('Choose image or GIF…')),
        const SizedBox(height: 12),
        if (_name != null) Text(_name!),
        const SizedBox(height: 8),
        PixelPreview(image: _preview, aspect: p.width / p.height),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Store on panel'),
          subtitle: Text(_save ? 'Will be saved as program slot ${s.store.nextSlot()}' : 'Show now, don\'t keep'),
          value: _save,
          onChanged: (v) => setState(() => _save = v),
        ),
        FilledButton.icon(
          onPressed: _gif == null || busy ? null : () => run('Upload', _send),
          icon: const Icon(Icons.upload),
          label: const Text('Send to display'),
        ),
        statusBar(context),
      ]);
}
