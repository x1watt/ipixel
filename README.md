# iPixel Open

Open-source control for **iPixel Color** Bluetooth LED panels (the cheap pixel signs and boards that
advertise as `LED_BLE_xxxxxxxx`). You can use them from **Linux, Windows, macOS and Android** without
the official phone app, or turn one into a small **improvised display** for your desktop.

* 📄 A complete **BLE protocol specification**: [docs/ble-protocol.md](docs/ble-protocol.md)
* 🎯 A pure-**Dart** protocol library that works with any Bluetooth stack
* 🖥️ A **Flutter app** with text, images/GIFs, brightness/power/clock, and a see-through **viewfinder**
  that mirrors any part of your screen to the panel 1:1
* ⌨️ A **command-line tool** for Linux

> Status: verified on a 64×16 panel (`LED_BLE_3E4F7EB7`, CID 0007 / PID 04). The protocol covers
> all 36 panel sizes the official app knows (16×16 up to 640×64). Other sizes should work but are
> untested. Reports are welcome.

---

## Features

| | GUI | CLI |
|---|:-:|:-:|
| Scan & connect (no pairing); keeps running in the background on Android (optional) | ✅ | ✅ |
| **Fun**: 35 live scenes rendered by the app and streamed at up to 9 fps: clocks (digital, analog, binary, date), Pomodoro timer, stopwatch, countdown-to-date, plasma / fire / matrix / rainbow / starfield / warp / sparkle / bouncing balls / Game of Life / lava lamp, text effects (rainbow, typewriter, wave, fire…), ticker, icon parade, 10 ready-made signs (ON AIR, OPEN, DND…), system monitor, progress bar, status icons, and 5 games (Snake, Pong, Breakout, Flappy, Tetris) with keyboard (arrows/WASD) or on-screen controls, auto-players, speed and brightness controls | ✅ | – |
| Text programs the panel plays by itself: 9 firmware animations, alignment, 8 gradient presets, speed, 16/32 px | ✅ | ✅ |
| Images and animated GIFs (rescaled to the panel) | ✅ | ✅ |
| **Draw**: pixel-art editor, live on the panel (pen, eraser, mirrors), storable as a program | ✅ | – |
| **Music**: microphone visualizer, either drawn by the panel firmware (7 styles) or by the app | ✅ | – |
| **Viewfinder**: see-through frame, whatever is under it goes to the LED (1:1, 2×, 3×) | ✅ Linux Wayland | – |
| **Programs**: stored slots, playlist, delete | ✅ | – |
| **Tools**: 10 clock faces, countdown, stopwatch, scoreboard, bike signs, scheduled on/off, picture alarms, password, brightness / power / flip | ✅ | partly |
| Delivery confirmed by the display's own acks; `hwcheck` reports what a panel supports | ✅ | ✅ |

## Quick start

### GUI (Flutter)

```bash
cd dart/ipixel_app
flutter run -d linux        # or: -d windows, -d macos, or a connected Android phone
```

1. The app lists nearby `LED_BLE_…` displays. Click one to connect.
2. **Text**: type, pick a color and effect, then press **Send**.
3. **Image / GIF**: choose a file, preview it at panel resolution, then send it.
4. **Viewfinder** (Linux/Wayland): the framed hole in the window is transparent. Move the window
   over whatever you want on the LED (a chat badge, a tiny graph, a game sprite) and press
   **Go live**. GNOME shows its *Share screen* dialog once per session: pick the monitor the window
   is on. Nothing is remembered or stored. The panel updates about once a second.
5. **Control**: brightness, power, flip, clock faces, delete stored programs.

### CLI (Linux)

```bash
cd dart/ipixel_cli
dart run bin/ipixel.dart info                      # panel size + firmware info
dart run bin/ipixel.dart text "Hello" ff8800       # orange scrolling text
dart run bin/ipixel.dart gif party.gif             # any image/GIF, rescaled
dart run bin/ipixel.dart brightness 40
dart run bin/ipixel.dart clock 2
dart run bin/ipixel.dart selftest                  # visual check of every feature
dart run bin/ipixel.dart hwcheck                   # which firmware features does this panel ack?
dart run bin/ipixel.dart bench                     # live-frame throughput
```

Add `-a C3:EF:3E:4F:7E:B7` to pick a specific display, or `-v` to print every packet.

## Requirements

| Platform | Bluetooth | Extra |
|---|---|---|
| Linux | BlueZ (standard), the user doesn't need root | Viewfinder: PipeWire + `gst-launch-1.0` with the pipewire plugin (`gstreamer1.0-tools gstreamer1.0-pipewire`) |
| Windows 10/11 | built-in (via `flutter_blue_plus_windows`) | – |
| macOS | built-in (CoreBluetooth) | Bluetooth permission prompt on first run |
| Android 6+ | built-in | Bluetooth permissions are requested on first scan |

Building needs Flutter ≥ 3.24 / Dart ≥ 3.4. The Android Gradle settings are tuned to build within
about 2 GB RAM.

## How it works (short version)

```
GATT service 0x00FA ─ write 0xFA02  →  [u16 len][u16 cmd][payload]      (little-endian)
                    └ notify 0xFA03 ←  05 00 <cmd> <status>   0=fail 1=ok 3=complete
```

* **Handshake** `0x8001` (sends the current time) returns the panel type, e.g. `0x83` = 64×16.
* **Simple commands**, e.g. brightness: `05 00 04 80 <0-100>`.
* **Uploads** (GIF `0x0003`, text `0x0100`, raw RGB frame `0x0000`) are split into 4 KB frames with
  a CRC32. The display acks every frame, so you know exactly when it worked.
* The panel has no fonts: the host draws each character as a 1-bit bitmap.

Everything is documented with byte-level examples in **[docs/ble-protocol.md](docs/ble-protocol.md)**.

## Repository layout

```
docs/
  ble-protocol.md        protocol specification (verified items marked ✅)
  reusable.md            index of reusable code blocks
dart/
  ipixel_protocol/       pure-Dart protocol: packets, panel table, text/image encoders, device API
  ipixel_bluez/          Linux BlueZ transport (scanner + BleLink), pure Dart
  ipixel_fx/             live effects engine: pixel canvas, fonts, 35 scenes incl. games (pure Dart)
  ipixel_cli/            command-line tool (Linux)
  ipixel_app/            Flutter app (Linux, Windows, macOS, Android)
ipixel/, tools/          Python (bleak) reference tools used to reverse-engineer and verify
```

### Using the library in your own app

```dart
import 'package:ipixel_protocol/ipixel_protocol.dart';

final device = IPixelDevice(myBleLink);      // implement BleLink for your BLE stack (4 members)
final panel = await device.handshake();      // PanelInfo(64x16, …)
await device.brightness(60);
await device.sendText('Hello', color: [0, 200, 255]);
await device.showRgb(rgbBytes);              // exactly width*height*3 bytes
```

Ready-made `BleLink`s: `FbpLink` (flutter_blue_plus, in the app) and `BlueZLink` (Linux, pure Dart).

## Development

```bash
cd dart/ipixel_protocol && dart test                 # golden bytes captured from real hardware
cd dart/ipixel_app && flutter test                   # widget tests with a fake panel
cd dart/ipixel_app && flutter test integration_test/text_real_test.dart -d linux
                                                     # end-to-end on a real panel nearby
```

## Not implemented / caveats

* Countdown, stopwatch, scoreboard and bike signs are sent exactly as the official app does, but
  the 64×16 test panel never acknowledges them; they may be for other models.
* Dual-panel "eyes", split-screen templates, camera projection and firmware updates (OTA) are
  left out. The viewfinder is Linux/Wayland-only for now; the microphone on Linux needs
  `parecord` (package `pulseaudio-utils`).
* Android builds have R8 shrinking disabled so they fit in 2 GB of RAM.

## Disclaimer

This is an independent project for interoperability. It is not affiliated with or endorsed by the
makers of the iPixel Color app or the LED hardware. No code from the official app is included; the
protocol was documented by observing and analysing it, then verified against real hardware.
Use at your own risk.

## License

[MIT](LICENSE)
