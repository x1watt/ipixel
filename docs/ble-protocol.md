# iPixel Color BLE protocol

Reverse-engineered from the Android app **iPixel Color** `com.wifiled.ipixels` **v3.8.1**
(APKPure XAPK, decompiled with jadx 1.5.1). The parts marked ✅ were **verified on real hardware**:
`LED_BLE_3E4F7EB7`, a 64×16 panel (CID `0007`, PID `04`, handshake code `0x83`), driven from
Linux/BlueZ with both the Python reference tool and the Dart package.

Source locations below are relative to the decompiled tree (`com/wifiled/ipixels/...`).

---

## 1. Discovery

| What | Value |
|---|---|
| Advertised name | `LED_BLE_<last 4 bytes of MAC>` (e.g. `LED_BLE_3E4F7EB7`) ✅ |
| Manufacturer data company id | bytes `54 52` ("TR") → `0x5254` when read little-endian (bleak / flutter_blue_plus) ✅ |
| Manufacturer payload (after id) | `[00] [72] [cidA] [cidB] [pid] [around] [size]` ✅ e.g. `00 72 00 07 04 00 83` |

The app accepts a device if its name contains `LED_BLE`, **or** if the manufacturer id is `0x5452`
and payload byte 1 is `0x72` (`core/BleManager$bleScanCallback$1.java`).

* **CID** = decimal(cidA) ‖ decimal(cidB), left-padded to 4 chars → `"0007"`.
* **PID** = decimal(pid) padded to 2 chars (3 if ≥ 100) → `"04"`.
* **size**: matched the handshake panel code (`0x83`) on the test device.

CID/PID select model quirks (password length, a few panel codes, OTA).

## 2. GATT

| Service / characteristic | UUID | Properties | Use |
|---|---|---|---|
| Service | `000000fa-0000-1000-8000-00805f9b34fb` | | main service ✅ |
| Write | `0000fa02-…` | write, write-without-response | host → device ✅ |
| Notify | `0000fa03-…` | notify | device → host replies ✅ |
| Service | `0000ae00-…` (`ae01` write-nr, `ae02` notify) | | JieLi chip OTA (ignore) |

Connection sequence used by the app (`core/BleManager.java`):

1. Connect, then enable notifications on `FA03`.
2. Request **MTU 512**. The app then writes in **509-byte** pieces (`perSendDataUnit`).
   With BlueZ the MTU is negotiated automatically (517 seen) ✅.
3. Send the **handshake** (§4.1) before anything else.

Use write-with-response. One *logical packet* longer than the ATT payload is simply written as
consecutive ATT writes. The device reassembles using the length field ✅ (no extra sub-header).

## 3. Packet format

All integers are **little-endian**.

```
offset  size  field
0       2     total packet length (including these 2 bytes)
2       2     command id
4       n     payload
```

Example: brightness 10 → `05 00 04 80 0a` (len 5, cmd 0x8004, payload 0x0a) ✅

### 3.1 Replies (notifications on FA03)

Most replies echo the command id in bytes 2..3. Short **acks** are 5 bytes:

```
05 00 <cmd lo> <cmd hi> <status>
status 0 = rejected / failed (e.g. wrong live-frame size, CRC mismatch)
       1 = OK  (single command accepted, or one upload frame received → send next)
       3 = complete (whole multi-frame upload received)
```

✅ Observed: brightness → `05 00 04 80 01`. A GIF upload → `05 00 03 00 03`. A text upload →
`05 00 00 01 03`. A live frame of the wrong size → `05 00 00 00 00`; the right size → `…01`.
**Use these acks to check that your code works.**

## 4. Simple commands

| Cmd | Name | Payload | Reply | Status |
|---|---|---|---|---|
| `0x8001` | handshake / getLedType | `hh mm ss lang` (+`week` on some CID 0001 models) | panel info (§4.1) | ✅ |
| `0x8001` | handshake (mecha models) | `yy MM dd week hh mm ss` | panel info | |
| `0x8005` | hardware info | – | `08 00 05 80 0e 02 07 04` on test unit | ✅ |
| `0x8004` | brightness | `level` 0–100 | ack | ✅ |
| `0x0107` | screen power | `1` on / `0` off | ack | ✅ |
| `0x8006` | upside-down | `1` / `0` | ack | ✅ |
| `0x0106` | clock face | `style, 12h?(1)/24h(0), showDate, yy-2000, MM, dd, week` | ack | ✅ |
| `0x8012` | set weekday | `week` | | |
| `0x0104` | DIY (draw) mode | `0` quit+restore, `1` enter+clear, `2` quit+keep, `3` enter keep | ack | ✅ |
| `0x0105` | DIY draw pixels | header byte 4 = moveType, then `R G B (x y)…` | none | ✅ |
| `0x8003` | delete all stored programs | – | | |
| `0x0102` | delete slots | `u16 count, slot…` | | |
| `0x0103` | text speed | `speed` | | |
| `0x0101` | exit current mode | – | | |
| `0x800D` | countdown | `flag, min, sec` | | |
| `0x8009` | stopwatch | `flag` | | |
| `0x800A` | scoreboard | `u16 a, u16 b` | | |
| `0x0006` | sport display | `mode, speed, decimal` | | |
| `0x0200` | music rhythm level | `level, mode` | none | |
| `0x0201` | music spectrum | `mode` + 11 bars (0–15) | none | |
| `0x0204` | set password | `enable, g1, g2, g3` (2-digit groups) | | |
| `0x0205` | verify password | `g1, g2, g3` | | |
| `0xC0xx` | OTA (`len, otaType, 0xC0, …`) | see `utils/OtaUpData.java` | | don't |

**Week** = Monday 1 … Sunday 7 (`baselib/utils/DateUtils.getWeekOfDate`).
DIY move types: 0 none, 1 horizontal mirror, 2 vertical mirror, 3 move all, 4 erase.

### 4.1 Handshake reply

```
0b 00 01 80 83 24 18 00 00 01 00          (test unit)
            ^^ panel code           ^^ byte 10: password enabled (1 → send 0x0205 first)
```

Panel code → app LED type → resolution (`ui/ChooseActivity.setLedType`, `AppConfig.ledSizeMap`):

| code | type | W×H | | code | type | W×H |
|---|---|---|---|---|---|---|
| 0x00/0x80 | 0 | 64×64 | | 0x90 | 16 | 256×32 |
| 0x81 | 2 (21 if CID 0001/PID 55) | 32×32 | | 0x91 | 17 | 320×32 |
| 0x82 | 4 (22 if CID 0001/PID 56) | 32×16 | | 0x92 | 18 | 384×32 |
| **0x83** | **3** | **64×16** ✅ | | 0x93 | 19 | 448×32 |
| 0x84 | 1 | 96×16 | | 0x94 | 20 | 16×16 |
| 0x85 | 5 | 64×20 | | 0x95 | 24 | 64×64 |
| 0x86 | 6 | 128×32 | | 0x96 | 25 | 96×64 |
| 0x87 | 7 | 144×16 | | 0x97 | 26 | 128×64 |
| 0x88 | 8 | 192×16 | | 0x98 | 27 | 160×64 |
| 0x89 | 9 (23 if CID 0001/PID 57) | 48×24 | | 0x99 | 28 | 192×64 |
| 0x8A | 10 | 64×32 | | 0x9A | 29 | 256×64 |
| 0x8B | 11 | 96×32 | | 0x9B | 30 | 320×64 |
| 0x8C | 12 | 128×32 | | 0x9C | 31 | 384×64 |
| 0x8D | 13 | 96×32 | | 0x9D–0xA0 | 32–35 | 448/512/576/640×64 |
| 0x8E | 14 | 160×32 | | | | |
| 0x8F | 15 | 192×32 | | | | |

**Upload frame size** (`ledFrameSize`): 12288 bytes for codes 0x00/0x80/0x81, otherwise 4096.

## 5. Bulk uploads (images, GIFs, text)

A payload is split into frames of `frameSize` bytes. Each frame is sent as one logical packet,
**and you wait for the ack before sending the next one** (`core/SendCore.payloadChannel`,
`sendDataInner`):

```
0   u16  packet length
2   u16  data type (command)
4   u8   option: 0 = first frame, 2 = continuation
5   u32  TOTAL payload length (all frames)
--- only for CRC types (video 0x0001, image 0x0002, GIF 0x0003, template 0x0004, text 0x0100):
9   u32  CRC-32 (zlib) of the TOTAL payload (same value in every frame)
13  u8   flag: 2 for GIF/template, 0 for image/text
14  u8   slot: program slot to store in (1…), or 101 (0x65) = show now, don't store
---
..       frame chunk
```

Acks: `…01` after each intermediate frame, `…03` after the last frame ✅.

### 5.1 Live RGB frame — type `0x0000` ✅

Payload = **RGB888, row-major, exactly W×H×3 bytes**. 9-byte header, no CRC, frame size 12288.
Shown immediately and not stored. If the length is wrong the device answers status 0.
Best for streaming or "screen mirroring" from a PC. The app enters DIY mode (`0x0104 01`) before
using it.

### 5.2 GIF — type `0x0003` ✅

Payload = a standard **GIF file** at panel resolution. flag = 2. The device plays the animation
using the GIF's own frame delays. The same path is used for static pictures (single-frame GIF).

### 5.3 Text — type `0x0100` ✅

The host renders every character itself. The firmware has no fonts.

```
header (14 B):
  u16 char count
  u8  horizontal align     u8 vertical align
  u8  effect (1 = scroll left ✅; others: see app's effect picker)
  u8  speed (0–100)
  u8  color mode (0 = solid)
  u8  R G B                text color
  u8  bg enabled           u8 R G B background
  [+3 B border type/speed/effect on LED types 16–19 and ≥ 24]
per character:
  0x80 R G B width height  + 1-bit bitmap
```

1-bit bitmap (`core/text/TextAgreement.getTextData`): rows of `ceil(width/8)*8` pixels, row-major.
**Bit i of each byte = pixel 8·byteIndex + i**, so the LSB is the leftmost pixel. The text height
matches the panel height (16 on the test unit).
Instead of `0x80`, a glyph record can be an embedded emoji JPEG (`8|9|10|11|12, u24 len, jpeg`).

### 5.4 Other data types (not verified)

`0x0001` video frames, `0x0002` still image, `0x0004` templates/sub-zones, alarm images
(`0x8000`, see `SendCore.payLoadAlarmClockData`).

## 6. Minimal session (hex)

```
-> 08 00 01 80 10 24 18 00                        handshake (16:36:24)
<- 0b 00 01 80 83 24 18 00 00 01 00               64x16, no password
-> 05 00 04 80 32                                 brightness 50
<- 05 00 04 80 01
-> fd 00 03 00 00 ee 00 00 00 3d 1c 75 56 02 65 + 238 B GIF
<- 05 00 03 00 03                                 GIF shown
```

## 7. Throughput

Live 64×16 frames (3081 B each), measured from Linux/BlueZ ✅:

| Write mode for bulk data | Frames/s |
|---|---|
| write-with-response (509 B pieces) | 4.4 |
| write-without-response, waiting for the per-frame ack | 9.0 |

The per-frame ack is enough flow control, so write-without-response is safe for uploads.

## 8. Implementations in this repo

* `dart/ipixel_protocol`: a pure-Dart, transport-agnostic implementation with golden-byte tests.
* `dart/ipixel_bluez`: the Linux BlueZ scanner and `BleLink`.
* `dart/ipixel_cli`: a Linux CLI (`dart run bin/ipixel.dart selftest`).
* `dart/ipixel_app`: a Flutter app (Linux/Windows/macOS/Android) with a see-through viewfinder.
* `ipixel/` and `tools/`: the Python (bleak) reference tool used for discovery and verification.
