import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:ipixel_bluez/ipixel_bluez.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

const usage = '''
usage: ipixel [-a ADDR] [-v] <command> [args]
  info                         panel + hardware info
  text "Hello" [RRGGBB] [effect] [speed]
  gif FILE                     any image/GIF, rescaled, shown (not stored)
  image FILE                   live RGB frame
  brightness 0..100 | power on|off | flip on|off | clock [style]
  selftest                     run the visual test sequence
  bench [N]                    stream N live frames and print the frame rate
  hwcheck                      exercise firmware features (clock styles, countdown, stopwatch,
                               scoreboard, playlist, text effects) and print the panel's acks''';

Future<void> main(List<String> argv) async {
  final args = [...argv];
  String? addr;
  var verbose = false;
  if (args.remove('-v')) verbose = true;
  final ai = args.indexOf('-a');
  if (ai >= 0) {
    addr = args[ai + 1];
    args.removeRange(ai, ai + 2);
  }
  if (args.isEmpty) {
    print(usage);
    exit(64);
  }
  final link = await BlueZLink.connect(address: addr);
  final d = IPixelDevice(link, log: verbose ? print : null);
  try {
    final p = await d.handshake();
    final cmd = args[0], a = args.skip(1).toList();
    void prog(double f) => stdout.write('\r${(f * 100).round()}%  ');
    switch (cmd) {
      case 'info':
        print('${link.device.address} ${link.device.name}  $p  hw: ${await d.hwInfo()}  mtu-3: ${link.maxWriteLength}');
      case 'text':
        final c = a.length > 1 ? a[1] : 'ffffff';
        final rgb = [for (var i = 0; i < 6; i += 2) int.parse(c.substring(i, i + 2), radix: 16)];
        print('status ${await d.sendText(a[0], color: rgb, effect: a.length > 2 ? int.parse(a[2]) : 1, speed: a.length > 3 ? int.parse(a[3]) : 50, save: false, onProgress: prog)}');
      case 'gif':
        final im = decodeAny(File(a[0]).readAsBytesSync())!;
        print('status ${await d.uploadGif(gifForPanel(im, p.width, p.height), save: false, onProgress: prog)}');
      case 'image':
        final im = decodeAny(File(a[0]).readAsBytesSync())!;
        print('status ${await d.showRgb(imageToRgb(im, p.width, p.height))}');
      case 'brightness':
        print(await d.brightness(int.parse(a[0])));
      case 'power':
        print(await d.power(a[0] == 'on'));
      case 'flip':
        print(await d.upsideDown(a[0] == 'on'));
      case 'clock':
        print(await d.clockMode(style: a.isEmpty ? 1 : int.parse(a[0])));
      case 'bench':
        final n = a.isEmpty ? 40 : int.parse(a[0]);
        await d.diyMode(DiyMode.enterClear);
        final frame = Uint8List(p.rgbFrameBytes);
        final sw = Stopwatch()..start();
        var ok = 0;
        for (var i = 0; i < n; i++) {
          final c = [(255, 0, 0), (0, 255, 0), (0, 0, 255)][i % 3];
          for (var j = 0; j < frame.length; j += 3) {
            frame[j] = c.$1;
            frame[j + 1] = c.$2;
            frame[j + 2] = c.$3;
          }
          if (await d.showRgb(frame) == 1) ok++;
        }
        print('$n frames in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s = '
            '${(n * 1000 / sw.elapsedMilliseconds).toStringAsFixed(1)} fps, acked ok $ok, link ${link.runtimeType}');
        await d.diyMode(DiyMode.quitDiscard);
      case 'hwcheck':
        await hwcheck(d, p);
      case 'selftest':
        await selftest(d, p);
      default:
        print(usage);
    }
  } finally {
    await d.close();
  }
}

Future<void> selftest(IPixelDevice d, PanelInfo p) async {
  final w = p.width, h = p.height;
  print('[1] DIY: yellow diagonal + white dot top-right');
  await d.diyMode(DiyMode.enterClear);
  await d.diyDraw([255, 255, 0], [for (var i = 0; i < h; i++) (i, i)]);
  await d.diyDraw([255, 255, 255], [(w - 1, 0)]);
  await Future.delayed(const Duration(seconds: 5));
  print('[2] live frame: magenta | cyan halves');
  final im = img.Image(width: w, height: h);
  for (final px in im) {
    px.setRgb(px.x < w ~/ 2 ? 255 : 0, px.x < w ~/ 2 ? 0 : 255, 255);
  }
  print('    status ${await d.showRgb(imageToRgb(im, w, h))}');
  await Future.delayed(const Duration(seconds: 5));
  print('[3] GIF: white/blue blink');
  await d.diyMode(DiyMode.quitDiscard);
  final a = img.Image(width: w, height: h)..clear(img.ColorRgb8(255, 255, 255));
  a.frameDuration = 400;
  final b = img.Image(width: w, height: h)..clear(img.ColorRgb8(0, 0, 255));
  b.frameDuration = 400;
  a.addFrame(b);
  print('    status ${await d.uploadGif(gifForPanel(a, w, h), save: false)}');
  await Future.delayed(const Duration(seconds: 5));
  print('[4] text "Dart works!" green');
  print('    status ${await d.sendText('Dart works!', color: [0, 255, 0], save: false)}');
}

/// Prints one line per firmware command with the panel's reply, so other panel owners can
/// report which features their model supports.
Future<void> hwcheck(IPixelDevice d, PanelInfo p) async {
  Future<void> step(String label, Future<Object?> Function() f, {int holdMs = 2500}) async {
    stdout.write('${label.padRight(34)} ');
    try {
      final r = await f();
      print(r is Reply ? r.toString() : '$r');
    } catch (e) {
      print('FAIL $e');
    }
    await Future.delayed(Duration(milliseconds: holdMs));
  }

  Future<Reply> req(Uint8List pkt) => d.request(pkt);
  await step('text blink, middle', () => d.sendText('BLINK', color: [255, 0, 255], effect: TextEffect.blink, save: false));
  await step('text gradient preset 0 scroll', () => d.sendText('GRADIENT', effect: TextEffect.scrollLeft,
      colorMode: TextColorMode.gradient(0), save: false), holdMs: 4000);
  await step('text snow', () => d.sendText('SNOW', color: [255, 255, 255], effect: TextEffect.snowflakes, save: false));
  await step('text laser', () => d.sendText('LASER', color: [0, 255, 0], effect: TextEffect.laser, save: false));
  for (var style = 1; style <= 3; style++) {
    await step('clock style $style 24h', () => req(IPixelCommands.clockMode(style: style, h24: true)));
  }
  await step('countdown start 0:10', () => req(IPixelCommands.countdown(1, 0, 10)), holdMs: 3000);
  await step('countdown pause', () => req(IPixelCommands.countdown(2, 0, 10)));
  await step('countdown reset', () => req(IPixelCommands.countdown(0, 0, 0)), holdMs: 500);
  await step('stopwatch start', () => req(IPixelCommands.stopwatch(1)), holdMs: 3000);
  await step('stopwatch reset', () => req(IPixelCommands.stopwatch(0)), holdMs: 500);
  await step('scoreboard 12:34', () => req(IPixelCommands.scoreboard(12, 34)));
  await step('sport mode 2 (go)', () => req(IPixelCommands.sport(2)));
  await step('rhythm bars mode 0', () async {
    for (var i = 0; i < 20; i++) {
      await d.rhythmBars(0, List.generate(11, (k) => ((i * 3 + k * 5) % 16)));
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return 'sent 20 frames (no reply expected)';
  });
  await step('playlist [1]', () => req(IPixelCommands.playlist([1])));
  await step('exit mode', () => req(IPixelCommands.exitMode()), holdMs: 0);
}
