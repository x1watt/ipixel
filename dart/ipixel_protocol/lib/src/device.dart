import 'dart:async';
import 'dart:typed_data';

import 'ble_link.dart';
import 'codec.dart';
import 'commands.dart';
import 'constants.dart';
import 'panel.dart';
import 'text.dart';

class IPixelException implements Exception {
  final String message;
  IPixelException(this.message);
  @override
  String toString() => 'IPixelException: $message';
}

/// High-level device API over a [BleLink].
class IPixelDevice {
  final BleLink link;
  final void Function(String line)? log;
  final _replies = StreamController<Reply>.broadcast();
  late final StreamSubscription<Uint8List> _sub;
  PanelInfo? panel;

  /// Use write-without-response for bulk uploads. The per-frame ack still provides
  /// flow control. Measured on a 64x16 panel: 4.4 fps (with response) -> 9 fps.
  bool bulkWithoutResponse = true;

  IPixelDevice(this.link, {this.log}) {
    _sub = link.notifications.listen((d) {
      final r = Reply(d);
      log?.call('<- $r');
      _replies.add(r);
    });
  }

  Stream<Reply> get replies => _replies.stream;

  Future<void> close() async {
    await _sub.cancel();
    await _replies.close();
    await link.disconnect();
  }

  /// Write a logical packet, splitting it into ATT-sized writes.
  Future<void> writePacket(Uint8List pkt, {bool withResponse = true}) async {
    log?.call('-> ${Reply(pkt.length > 24 ? pkt.sublist(0, 24) : pkt)}${pkt.length > 24 ? ' … (${pkt.length} B)' : ''}');
    final unit = link.maxWriteLength.clamp(20, maxAttPayload);
    for (var i = 0; i < pkt.length; i += unit) {
      await link.write(pkt.sublist(i, i + unit > pkt.length ? pkt.length : i + unit),
          withResponse: withResponse);
    }
  }

  /// Send a packet and wait for the reply carrying the same command id.
  Future<Reply> request(Uint8List pkt,
      {Duration timeout = const Duration(seconds: 3), bool withResponse = true}) async {
    final cmd = readU16le(pkt, 2);
    final fut = replies.firstWhere((r) => r.cmd == cmd).timeout(timeout,
        onTimeout: () => throw IPixelException('no reply to cmd 0x${cmd.toRadixString(16)}'));
    await writePacket(pkt, withResponse: withResponse);
    return fut;
  }

  /// Send without waiting for a reply (e.g. DIY drawing, rhythm).
  Future<void> fire(Uint8List pkt) => writePacket(pkt);

  /// Send and wait briefly for a reply; null if the panel stays silent. Use for commands
  /// some firmwares ack and others don't (countdown, stopwatch, scoreboard, sport).
  Future<Reply?> requestOptional(Uint8List pkt, {Duration wait = const Duration(milliseconds: 800)}) async {
    try {
      return await request(pkt, timeout: wait);
    } on IPixelException {
      return null;
    }
  }

  // ---- session ---------------------------------------------------------

  /// Must be the first command after connecting: syncs time and identifies the panel.
  Future<PanelInfo> handshake({String? cid, String? pid}) async {
    final r = await request(IPixelCommands.handshake());
    return panel = PanelInfo.fromHandshake(r.bytes, cid: cid, pid: pid);
  }

  Future<Reply> hwInfo() => request(IPixelCommands.hwInfo());
  Future<bool> brightness(int level) async => _ok(await request(IPixelCommands.brightness(level)));
  Future<bool> power(bool on) async => _ok(await request(IPixelCommands.power(on)));
  Future<bool> upsideDown(bool f) async => _ok(await request(IPixelCommands.upsideDown(f)));
  Future<bool> clockMode({int style = 1, bool h24 = true, bool showDate = false}) async =>
      _ok(await request(IPixelCommands.clockMode(style: style, h24: h24, showDate: showDate)));
  /// True while the panel is in DIY/drawing mode (live frames). Uploads leave it first.
  bool inDiy = false;

  Future<bool> diyMode(DiyMode m) async {
    // Some panels don't ack the mode switch (and won't while frames are streaming);
    // treat a silence as success rather than throwing an uncaught timeout.
    final r = await requestOptional(IPixelCommands.diyMode(m));
    inDiy = m == DiyMode.enterClear || m == DiyMode.enterKeep;
    return r == null || _ok(r);
  }

  Future<void> _leaveDiy() async {
    if (inDiy) await diyMode(DiyMode.quitDiscard);
  }
  Future<void> diyDraw(List<int> rgb, List<(int, int)> pts, {int moveType = 0}) =>
      fire(IPixelCommands.diyDraw(rgb, pts, moveType: moveType));
  Future<bool> deleteAll() async => _ok(await request(IPixelCommands.deleteAll()));
  Future<bool> deleteSlots(List<int> slots) async => _ok(await request(IPixelCommands.deleteSlots(slots)));
  Future<bool> playlist(List<int> slots) async => _ok(await request(IPixelCommands.playlist(slots)));
  Future<bool?> countdown(int flag, int min, int sec) async => _okOpt(await requestOptional(IPixelCommands.countdown(flag, min, sec)));
  Future<bool?> stopwatch(int flag) async => _okOpt(await requestOptional(IPixelCommands.stopwatch(flag)));
  Future<bool?> scoreboard(int a, int b) async => _okOpt(await requestOptional(IPixelCommands.scoreboard(a, b)));
  Future<bool?> sport(int mode, {int speed = 0, int tenths = 0}) async =>
      _okOpt(await requestOptional(IPixelCommands.sport(mode, speed: speed, tenths: tenths)));
  Future<bool?> exitMode() async => _okOpt(await requestOptional(IPixelCommands.exitMode()));
  Future<bool> schedule({required int index, required bool on, required int hour, required int minute,
          required List<bool> days, bool enabled = true}) async =>
      _ok(await request(IPixelCommands.schedule(index: index, on: on, hour: hour, minute: minute, days: days, enabled: enabled)));
  Future<bool> setPassword(bool enable, String digits) async =>
      _ok(await request(IPixelCommands.setPassword(enable, _groups(digits))));
  Future<bool> verifyPassword(String digits) async => _ok(await request(IPixelCommands.verifyPassword(_groups(digits))));
  static List<int> _groups(String d) => [for (var i = 0; i + 1 < d.length; i += 2) int.parse(d.substring(i, i + 2))];

  /// Music level (0..7) for the firmware's level-style visualizers; no reply.
  Future<void> rhythmLevel(int level, int mode) => fire(IPixelCommands.rhythm(level, mode));

  /// Music spectrum, 11 bars 0..15, for firmware spectrum styles [mode] 0..4; no reply.
  Future<void> rhythmBars(int mode, List<int> bars) => fire(IPixelCommands.rhythmChart(mode, bars));

  bool _ok(Reply r) => r.status == null || r.status == AckStatus.ok;
  bool? _okOpt(Reply? r) => r == null ? null : _ok(r);

  // ---- uploads ---------------------------------------------------------

  PanelInfo get _panel => panel ?? (throw IPixelException('call handshake() first'));

  /// Upload a multi-frame payload, waiting for the ack after every frame.
  /// Calls [onProgress] with 0..1. Returns the final status.
  Future<int> upload(List<Uint8List> packets,
      {void Function(double)? onProgress, Duration timeout = const Duration(seconds: 8)}) async {
    var last = -1;
    for (var i = 0; i < packets.length; i++) {
      final r = await request(packets[i], timeout: timeout, withResponse: !bulkWithoutResponse);
      last = r.status ?? -1;
      onProgress?.call((i + 1) / packets.length);
      if (last == AckStatus.fail) throw IPixelException('device rejected frame $i ($r)');
      if (last == AckStatus.done) break;
    }
    return last;
  }

  /// Show raw RGB888 (exactly width*height*3 bytes) immediately. Not stored.
  Future<int> showRgb(Uint8List rgb, {void Function(double)? onProgress}) {
    if (rgb.length != _panel.rgbFrameBytes) {
      throw IPixelException('frame must be ${_panel.rgbFrameBytes} bytes, got ${rgb.length}');
    }
    return upload(buildDataPackets(cmd: Cmd.liveFrame, data: rgb, frameSize: 12288, withCrc: false),
        onProgress: onProgress);
  }

  /// Upload a GIF file (already at panel resolution). [save]=false shows it without storing.
  Future<int> uploadGif(Uint8List gif, {int slot = 1, bool save = true, void Function(double)? onProgress}) async {
    await _leaveDiy();
    return upload(
          buildDataPackets(cmd: Cmd.gif, data: gif, frameSize: _panel.frameSize, withCrc: true,
              flag: 2, slot: save ? slot : 101),
          onProgress: onProgress);
  }

  /// Alarm [index] (0..9) at [hour]:[minute] on [days] (Mon..Sun) showing [image] (GIF/PNG bytes).
  /// [ringSeconds] one of 10, 30, 60, 300, 900. Re-send with enabled=false to disable.
  Future<int> uploadAlarm({required int index, required int hour, required int minute, required List<bool> days,
      required Uint8List image, bool enabled = true, int ringSeconds = 30, bool buzzer = true, int type = 1,
      void Function(double)? onProgress}) async {
    await _leaveDiy();
    final fs = _panel.frameSize;
    final crc = crc32(image);
    final packets = <Uint8List>[];
    for (var off = 0, n = 0; off < image.length; off += fs, n++) {
      final chunk = image.sublist(off, off + fs > image.length ? image.length : off + fs);
      final hdr = [
        ...u16le(24 + chunk.length), ...u16le(Cmd.alarm), index, IPixelCommands.weekMask(days, enabled: enabled),
        hour, minute, ...u16le(ringSeconds), type, buzzer ? 1 : 0, n == 0 ? 0 : 2, ...u32le(image.length), ...u32le(crc),
        0, 0, index + 120,
      ];
      packets.add(Uint8List.fromList([...hdr, ...chunk]));
    }
    return upload(packets, onProgress: onProgress);
  }

  /// Render and upload text.
  Future<int> sendText(String text,
      {List<int> color = const [255, 255, 255],
      List<int>? background,
      int effect = TextEffect.scrollLeft,
      int speed = 50,
      int? height,
      int hAlign = TextAlign.center,
      int vAlign = TextVAlign.middle,
      int colorMode = TextColorMode.solid,
      GlyphRenderer renderer = bitmapFontGlyph,
      int slot = 1,
      bool save = true,
      void Function(double)? onProgress}) async {
    await _leaveDiy();
    final p = _panel;
    final data = encodeText(text,
        color: color, background: background, effect: effect, speed: speed, hAlign: hAlign, vAlign: vAlign,
        colorMode: colorMode, height: height ?? (p.height > 32 ? 32 : p.height), renderer: renderer, ledType: p.ledType);
    return upload(
        buildDataPackets(cmd: Cmd.text, data: data, frameSize: p.frameSize, withCrc: true,
            flag: 0, slot: save ? slot : 101),
        onProgress: onProgress);
  }
}
