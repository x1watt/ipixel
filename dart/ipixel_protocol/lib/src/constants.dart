/// GATT layout (16-bit UUIDs on the Bluetooth base UUID).
class IPixelUuids {
  static const service = '000000fa-0000-1000-8000-00805f9b34fb';
  static const write = '0000fa02-0000-1000-8000-00805f9b34fb'; // write / write-without-response
  static const notify = '0000fa03-0000-1000-8000-00805f9b34fb'; // notify (device replies)
  /// JieLi OTA service also present on the device; not needed for normal control.
  static const jieliOtaService = '0000ae00-0000-1000-8000-00805f9b34fb';
}

/// Company id carried in advertisement manufacturer data (bytes "TR" on air,
/// i.e. 0x5254 when read little-endian as most stacks do).
const int ipixelManufacturerIdLE = 0x5254;

/// Advertised name prefix.
const String ipixelNamePrefix = 'LED_BLE';

/// Command ids (u16, sent little-endian in bytes 2..3 of every packet).
class Cmd {
  // data channels (multi-frame uploads)
  static const liveFrame = 0x0000; // raw RGB888 frame (app "camera" type)
  static const video = 0x0001;
  static const image = 0x0002;
  static const gif = 0x0003;
  static const template = 0x0004;
  static const text = 0x0100;

  // simple commands
  static const exitMode = 0x0101;
  static const deleteSlots = 0x0102;
  static const textSpeed = 0x0103;
  static const diyMode = 0x0104;
  static const diyDraw = 0x0105;
  static const clockMode = 0x0106;
  static const power = 0x0107;
  static const rhythm = 0x0200; // music level (fire-and-forget)
  static const rhythmChart = 0x0201; // music spectrum bars
  static const setPassword = 0x0204;
  static const verifyPassword = 0x0205;
  static const sport = 0x0006;

  static const alarm = 0x8000; // alarm with image (multi-frame)
  static const handshake = 0x8001; // a.k.a. getLedType; also sets time
  static const deleteAll = 0x8003;
  static const brightness = 0x8004;
  static const hwInfo = 0x8005;
  static const upsideDown = 0x8006;
  static const eyesMode = 0x8007; // dual-panel "eyes" remote: [mode][lang]
  static const playlist = 0x8008; // which stored slots to play, in order
  static const stopwatch = 0x8009;
  static const scoreboard = 0x800A;
  static const countdown = 0x800D;
  static const schedule = 0x8011; // scheduled power on/off
  static const setWeek = 0x8012;
}

/// Status byte (index 4) in 5-byte ack notifications `05 00 <cmd lo> <cmd hi> <status>`.
class AckStatus {
  static const fail = 0; // rejected (e.g. wrong frame size, CRC error)
  static const ok = 1; // command accepted / data frame received, send next
  static const done = 3; // whole multi-frame upload received
}

/// Largest single ATT write the official app uses (MTU 512 - 3).
const int maxAttPayload = 509;
