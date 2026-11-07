import 'dart:typed_data';

import 'codec.dart';
import 'constants.dart';

/// Monday = 1 … Sunday = 7 (what the firmware expects; same as DateTime.weekday).
int _week(DateTime t) => t.weekday;

/// DIY (drawing) mode argument for [IPixelCommands.diyMode].
enum DiyMode {
  quitDiscard(0), // leave DIY, restore previous program
  enterClear(1), // enter DIY and clear the screen
  quitKeep(2), // leave DIY, keep what was drawn
  enterKeep(3); // enter DIY without clearing

  final int value;
  const DiyMode(this.value);
}

/// Pure packet builders for all single-packet commands. No I/O.
class IPixelCommands {
  /// Handshake ("getLedType"). Sends current time; reply describes the panel.
  /// Some CID 0001 products (PID 54/55/56/...) append the weekday – pass [withWeek].
  static Uint8List handshake({DateTime? now, int language = 0, bool withWeek = false}) {
    final t = now ?? DateTime.now();
    return frame(Cmd.handshake,
        [t.hour, t.minute, t.second, language, if (withWeek) _week(t)]);
  }

  /// Handshake variant for "mecha" products: full date + time.
  static Uint8List handshakeMecha({DateTime? now}) {
    final t = now ?? DateTime.now();
    return frame(Cmd.handshake,
        [t.year - 2000, t.month, t.day, _week(t), t.hour, t.minute, t.second]);
  }

  static Uint8List hwInfo() => frame(Cmd.hwInfo);
  static Uint8List brightness(int level) => frame(Cmd.brightness, [level.clamp(0, 100)]);
  static Uint8List power(bool on) => frame(Cmd.power, [on ? 1 : 0]);
  static Uint8List upsideDown(bool flipped) => frame(Cmd.upsideDown, [flipped ? 1 : 0]);
  static Uint8List setWeek({DateTime? now}) => frame(Cmd.setWeek, [_week(now ?? DateTime.now())]);
  static Uint8List deleteAll() => frame(Cmd.deleteAll);
  static Uint8List exitMode() => frame(Cmd.exitMode);
  static Uint8List textSpeed(int speed) => frame(Cmd.textSpeed, [speed]);

  /// Delete stored program slots.
  static Uint8List deleteSlots(List<int> slots) =>
      frame(Cmd.deleteSlots, [...u16le(slots.length), ...slots]);

  /// Built-in clock face (1-based [style]; most panels have 8-10); also syncs the date.
  /// Byte 5 is 0 for 12-hour and 1 for 24-hour display (BaseSend.sendColockMode).
  static Uint8List clockMode({int style = 1, bool h24 = true, bool showDate = false, DateTime? now}) {
    final t = now ?? DateTime.now();
    return frame(Cmd.clockMode,
        [style, h24 ? 1 : 0, showDate ? 1 : 0, t.year - 2000, t.month, t.day, _week(t)]);
  }

  /// Play the given stored slots in order (firmware "channel list"). Ack status 1 = accepted.
  static Uint8List playlist(List<int> slots) => frame(Cmd.playlist, [slots.length, 0, ...slots]);

  /// Scheduled power on/off entry. [index] 0-based (max 10), [enabled] + [days] (Mon..Sun) form
  /// the week bitmask: bit0 = enabled, bit1 = Mon … bit7 = Sun.
  static Uint8List schedule({required int index, required bool on, required int hour, required int minute,
      required List<bool> days, bool enabled = true}) =>
      frame(Cmd.schedule, [on ? 1 : 0, index, weekMask(days, enabled: enabled), hour, minute]);

  static int weekMask(List<bool> days, {bool enabled = true}) {
    var m = enabled ? 1 : 0;
    for (var i = 0; i < 7 && i < days.length; i++) {
      if (days[i]) m |= 1 << (i + 1);
    }
    return m;
  }

  /// Riding/sport sign: 0 left, 1 right, 2 go, 3 stop, 4 SOS, 5 flash, 6 speed ([speed] km/h, [tenths]).
  static Uint8List sport(int mode, {int speed = 0, int tenths = 0}) => frame(Cmd.sport, [mode, speed, tenths]);

  static Uint8List diyMode(DiyMode mode) => frame(Cmd.diyMode, [mode.value]);

  /// Paint [points] (x,y pairs) with [rgb] while in DIY mode. No reply is sent.
  /// [moveType]: 0 none, 1 h-mirror, 2 v-mirror, 3 move-all, 4 erase.
  static Uint8List diyDraw(List<int> rgb, List<(int, int)> points, {int moveType = 0}) {
    final payload = [...rgb, for (final p in points) ...[p.$1, p.$2]];
    final len = 5 + payload.length;
    return Uint8List.fromList([...u16le(len), ...u16le(Cmd.diyDraw), moveType, ...payload]);
  }

  /// Countdown. [flag]: 0 reset, 1 start, 2 pause, 3 resume. Reset sends 0:00.
  static Uint8List countdown(int flag, int minutes, int seconds) =>
      frame(Cmd.countdown, [flag, minutes, seconds]);

  /// Stopwatch. [flag]: 0 reset, 1 start, 2 pause, 3 resume.
  static Uint8List stopwatch(int flag) => frame(Cmd.stopwatch, [flag]);

  /// Two scores (0..999, or 0..99 on narrow panels), little-endian.
  static Uint8List scoreboard(int a, int b) => frame(Cmd.scoreboard, [...u16le(a), ...u16le(b)]);

  /// Music rhythm level/mode (fire-and-forget).
  static Uint8List rhythm(int level, int mode) => frame(Cmd.rhythm, [level, mode]);

  /// Music spectrum: 11 bars, each 0..15.
  static Uint8List rhythmChart(int mode, List<int> bars) =>
      frame(Cmd.rhythmChart, [mode, for (var i = 0; i < 11; i++) i < bars.length ? bars[i].clamp(0, 15) : 0]);

  /// Password as 2-digit groups, e.g. "123456" -> [12, 34, 56].
  /// 4-digit models (CID 0035/PID 01, CID 0001/PID 130) use two groups; a 0 is padded.
  static Uint8List setPassword(bool enable, List<int> groups) =>
      frame(Cmd.setPassword, [enable ? 1 : 0, ..._pad3(groups)]);
  static Uint8List verifyPassword(List<int> groups) => frame(Cmd.verifyPassword, _pad3(groups));

  static List<int> _pad3(List<int> g) => [for (var i = 0; i < 3; i++) i < g.length ? g[i] : 0];
}
