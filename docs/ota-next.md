# Resume plan — custom firmware for an XPRS display

Where we stopped (2026-11-08) and exactly how to pick up. Full detail is in `ota.md`; this is the
short, actionable version.

## The goal (unchanged)

The iPixel panel **itself** receives XPRS messages over BLE and displays them — standalone custom
firmware, not a host-driven display. The user will adapt an XPRS node to emit a **legacy** BLE
bearer the panel's radio can hear (the AC695x SDK has a BLE central/observer role), so the radio is
not a blocker. The remaining job is getting our own code onto the chip.

## What is already confirmed (don't re-litigate)

- **Chip:** JieLi **AC695x** (BR22/BR23 family; `br23loader`/`br22loader` both bundled in
  `jl-uboot-tool`). A PCB photo would pin BR22 vs BR23 but isn't blocking.
- **`.ufw` format:** fully parsed — `tools/ufw_parse.py` (32-byte directory entries, file-relative
  offsets, `JLUFW` trailer, a SHA-256-shaped signature footer).
- **ENC encryption: broken.** Continuous CRC16-CCITT LFSR stream, 16-bit root key. Sibling image
  `TR2603R006-01.ufw` → key **`0x1ce6`** (`tools/jl_decrypt.py`). Our own panel's key is unknown
  (model-specific; the server serves no image for our board).
- **OTA over BLE is OPEN and AUTHENTICATED** (verified live on the panel):
  - Service `0x00AE` is always exposed (write `AE01`, notify `AE02`), no trigger.
  - Auth = Bluetooth **E1/SAFER+** with a fixed key — `dart/ipixel_bluez/lib/jl_auth.dart`
    (`selftest` passes). Handshake + `GET_TARGET_INFO` work end to end.

So "can we rewrite the firmware?" — **the write channel is confirmed open.** The open work is
producing a `.ufw` the bootloader will *accept*, and flashing it.

## The two remaining blockers (tomorrow's real work)

1. **Build an acceptable image** — needs the JieLi **AC695x SDK** (JieLi-Tech / YunThinker
   "soundbox" SDK) *and* this board's **LED-driver config** (how the 64×16 is wired). The LED config
   lives in our stock firmware (OTA can't read it back) or on the PCB.
2. **Signature footer** — is it a plain hash (forgeable, we're fine) or a real signature against a
   vendor key (then a custom image is rejected)? **Unknown; this is the one possibly-fatal gate.**

## Pick up here (in order)

1. **Non-destructive OTA negotiation probe** (safe, do first): extend `bin/ota_auth_probe.dart` to
   also send `OTA_INQUIRE_DEVICE_IF_CAN_UPDATE (0xE2)` and `GET_DEVICE_UPDATE_FILE_INFO_OFFSET
   (0xE1)` after auth, and parse `GET_TARGET_INFO`'s 62-byte TLV (via `TargetInfoResponse.java`) to
   read the firmware version + what the device checks before accepting an image. No erase happens
   until blocks are sent + committed. **Do NOT send `ENTER_UPDATE_MODE (0xE3)` / blocks `(0xE5)`
   without the user's OK — that's where destructive begins.**
2. **Get the AC695x SDK** and locate its `.ufw` packaging tool (to learn the signature scheme and
   build a test image). Then test whether the panel accepts an SDK-built image (answers blocker 2).
3. Only once an image is accepted: add the XPRS RX (legacy-BLE scan) + the display logic. The
   display/parse logic already exists in Dart as reference — `ipixel_fx` `XprsPacket` (parser) and
   `XprsMessageScene` (64×16 renderer) — to be reimplemented in C against the panel's framebuffer.

## Environment to rebuild — the scratchpad is session-specific and may be gone tomorrow

In-repo (persistent): `tools/fetch_firmware.py`, `tools/ufw_parse.py`, `tools/jl_decrypt.py`,
`dart/ipixel_bluez/lib/jl_auth.dart` + `bin/{gatt_discover,ota_probe,ota_auth_probe}.dart`.

Regenerate the rest:
- **Firmware images:** `cd ~/code/2026/ipixel && python3 -I tools/fetch_firmware.py jieli`
  (downloads `TR2603R006-01.ufw` into `firmware/`, gitignored). Then
  `python3 -I tools/ufw_parse.py firmware/TR2603R006-01.ufw --extract firmware/extracted` and
  `python3 -I tools/jl_decrypt.py firmware/extracted/ble_app_ota.bin --key 0x1ce6 -o /tmp/app.dec`.
- **jl-uboot-tool:** `git clone https://github.com/kagaimiq/jl-uboot-tool` (bundles loader blobs;
  BR23 = "Working"). Only needed if we go the USB-flash route.
- **APK + decompiled SDK** (for RCSP/OTA details): the app is `com.wifiled.ipixels` (v3.8.1);
  decompile with `jadx`; the OTA protocol is under `com.jieli.jl_bt_ota`
  (`constant/Command.java`, `tool/ParseHelper.java`, `model/response/TargetInfoResponse.java`).
  Extract `libjl_ota_auth.so` from the `config.arm64_v8a` split APK (`unzip -j … lib/*/libjl_ota_auth.so`).
  Everything we needed from it is already distilled into `jl_auth.dart`.

## Quick reference

- Probe the panel: `cd dart/ipixel_bluez && ~/flutter/bin/dart run ipixel_bluez:ota_auth_probe`
  (add `selftest` to just validate E1). GATT dump: `… ipixel_bluez:gatt_discover`.
- Run via `~/flutter/bin/dart` — `dart` is not on PATH; it's bundled with Flutter.
- Free the panel from the app first if needed; it drops BLE when the app holds it.
- RCSP TX frame: `FE DC BA | flags | opcode | len(2, BE) | [sn][params] | EF`; `flags = 0xC0` for a
  command wanting a response. `GET_TARGET_INFO = 0x03`, params `[sn] FF FF FF FF 00`.
- OTA opcodes: inquire `0xE2`, file-info-offset `0xE1`, enter-update `0xE3`, send-block `0xE5`,
  reboot `0xE7`.
- E1 auth key/addr and the handshake live in `jl_auth.dart`.
