# Reusable code

Pieces worth reusing when adding features. Reuse these before writing new code.

## Dart protocol (`dart/ipixel_protocol/lib/src/`)

| Block | File | Reuse for |
|---|---|---|
| `frame(cmd, payload)` | codec.dart | **every** new single-packet command (length + cmd header) |
| `buildDataPackets(...)` | codec.dart | any multi-frame upload (video `0x0001`, image `0x0002`, template `0x0004`, alarm images) |
| `crc32()` | codec.dart | zlib-compatible CRC (also OTA) |
| `u16le / u32le / readU16le` | codec.dart | byte packing |
| `Reply` (cmd / status / isAck) | codec.dart | parsing any notification |
| `IPixelDevice.request()` / `requestOptional()` / `fire()` / `upload()` | device.dart | new commands: `request` waits for the reply with the same cmd id; `upload` is the per-frame ack loop with progress |
| `IPixelDevice.inDiy` + `_leaveDiy()` | device.dart | any new upload type must leave DIY mode first (or the panel keeps showing the live frame) |
| `BleLink` interface | ble_link.dart | porting to a new BLE stack: implement 4 members |
| `PanelInfo.fromHandshake` + `ledTypeSizes` | panel.dart | anything that needs the panel resolution |
| `IPixelAdvert.matches / fromManufacturerData` | advert.dart | scan filters on any platform |
| `pack1bit(Glyph)`, `bitmapFontGlyph` | text.dart | 1-bit bitmaps; reliable pure-Dart glyphs (Flutter's offscreen text raster returned empty images on Linux) |
| `imageToRgb`, `gifForPanel`, `decodeAny` | images.dart | converting user images/GIFs to panel format |

## Effects engine (`dart/ipixel_fx/lib/src/`)

| Block | File | Reuse for |
|---|---|---|
| `PanelCanvas` (set/get/line/rect/circle/fade/drawImage/toImage) | canvas.dart | any new scene or drawing feature |
| `hsv / mix / dim / rgb` | canvas.dart | colour maths everywhere |
| `PixelFont` (4 sizes) + `Marquee` | fonts.dart | crisp text on the panel; `tools/gen_pixel_fonts.py` regenerates the tables |
| `Icons8` | icons.dart | 8×8 glyphs for signs/status |
| `Scene` / `SimpleScene` / `SceneInput` | scene.dart | the contract for a new effect, widget or game |
| `LivePlayer` | player.dart | streaming any scene; dedups identical frames |
| `sceneCatalog` | catalog.dart | register new scenes here to appear in the Fun page |
| `GameScene` (auto-pilot after idle, `touched()`, `autoRestart()`) + `_gameOver()` | scenes/games.dart | base for any new game |
| `LivePlayer.speed` / `.brightness` | player.dart | global knobs; don't re-implement per scene |

## Transports

| Block | File |
|---|---|
| `BlueZScanner` (throttled: emits only on display changes, ≤ 2/s) + `BlueZLink` (AcquireWrite socket, 9 fps) | dart/ipixel_bluez/lib/ipixel_bluez.dart |
| `FbpLink` (flutter_blue_plus / _windows) | dart/ipixel_app/lib/fbp_link.dart |
| `DisplayFinder` (picks BlueZ on Linux, FBP elsewhere) | dart/ipixel_app/lib/transport.dart |

## App (`dart/ipixel_app/lib/`)

| Block | File | Reuse for |
|---|---|---|
| `RunAction` mixin (status, progress, ack wording) | pages/common.dart | any page that sends something |
| `ColorRow`, `PageBody`, `PixelPreview` | pages/common.dart | consistent UI pieces |
| `rgbToRgba`, `rgbaToPanelRgb` | pages/pixels.dart | showing or creating panel-sized frames in Flutter |
| `PortalScreenCast` (no persistence, cursor hidden) | viewfinder/portal.dart | any Wayland screen capture |
| `ScreenCapture` (native-size probe + gst pipe) | viewfinder/capture.dart | raw RGB frames from PipeWire |
| `locateViewfinder`, `cropExact`, `cropHole` | viewfinder/locate.dart | finding a marker frame and making 1:1 / zoomed crops |
| `FakeLink` (acks like a real panel) | test/widget_test.dart | widget tests without hardware |
| `Session` (device + store + player + mic, `stopLive()`) | session.dart | every feature page; call `stopLive()` before uploads |
| `MicAnalyzer` (PCM → level + 11 bands, FFT) | mic.dart | anything audio-reactive |
| `ProgramsStore` (slots, playlist, `nextSlot()`) | programs_store.dart | any feature that stores on the panel |
| `BackgroundMode` | background.dart | Android foreground-service toggle |
| `_DPad` | pages/fun_page.dart | on-screen controls for interactive scenes |
| `_GridPainter` + stroke batching | pages/draw_page.dart | pixel editors |
| integration tests on the real panel | integration_test/*.dart | verifying GUI flows end to end |

## Python reference (`ipixel/__init__.py`)

`frame`, `_send_frames`, `pack_1bit`, `encode_text` and `PANEL_TYPES` are handy for quick hardware
experiments before porting to Dart.

## Firmware / OTA tooling (`tools/`)

| Piece | File | Reuse when |
| --- | --- | --- |
| `fetch_firmware.py` (AES + form OTA queries, family + JieLi sweeps) | tools/fetch_firmware.py | pulling any iPixel/Heaton firmware image from the server |
| `ufw_parse.py` (JieLi `.ufw` directory parser + extractor) | tools/ufw_parse.py | inspecting/carving any JieLi AC695x/BR22 `.ufw` |
| `entropy`, `find_directory` helpers | tools/ufw_parse.py | fingerprinting encrypted vs plaintext firmware regions |

## Candidates (not extracted yet)

* A "time payload" helper (`hh mm ss` / `yy MM dd week`), duplicated in `IPixelCommands.handshake`,
  `handshakeMecha` and `clockMode`.
* `_same(a, b)` frame comparison, duplicated in viewfinder_page.dart. Move it to pixels.dart if it's
  needed a third time.
