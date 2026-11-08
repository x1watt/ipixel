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

## Updated blockers (signature resolved; the real gate is the OEM image)

Resolved by research + the open BR23 bootloader (`Jieli-Tech/fw-Bootloader`, AC695x→`br23`):
- **No cryptographic signature.** The br23 uboot has no `rsa/ecc/ed25519/sha256/signature` check;
  JieLi OTA verifies with CRC16 + an SDK-ID identity match + a per-PID "chipkey" (a packing/scramble
  key, not a signature). The `.ufw`'s 32-byte footer isn't a SHA-256 of any simple prefix either —
  consistent with a CRC/MAC over the *unscrambled* content, not a blocker.
- **Prior art:** `ElectronicCats/jieli-ble-badge-research` got a self-built image accepted over BLE
  OTA on a sibling JieLi part (AC707N/BR35). It required: **repack into the OEM `.ufw`**, preserve
  the OEM uboot byte-for-byte, recompute all CRCs, and embed the per-PID chipkey. A raw SDK `make`
  image **bricks silently** — do not flash one.

**The one hard blocker left: our panel's OEM firmware image.** We need it for the OEM uboot, the
per-PID chipkey, and the LED-driver config. We can't get it remotely — the vendor server has no
image for our board, OTA can't read flash back, and the USB port didn't enumerate. So this route is
now gated on a **physical SPI-flash dump**: open the case, then either `jl-uboot-tool` over the
chip's USB pads (USB_KEY entry) or a SPI clip on the ZB25VQ32 flash. `jl-uboot-tool` is staged in
the scratchpad (`jlut/`), `fw-Bootloader` (br23 uboot + update_tools) is cloned (`fwboot/`), and
`fw-AC63_BT_SDK` ("compatible with AC69 series without audio") is the app-build base to fetch.

Everything software/remote is done: OTA write channel + E1 auth proven, no signature, dual-bank
brick-safety confirmed. Resuming means deciding on physical access to dump the stock image.

## Definitive blocker: the per-device eFuse chipkey (verified against ElectronicCats' toolkit)

`ElectronicCats/jieli-ble-badge-research` is the only group to custom-flash these JieLi chips over
BLE; their tooling is the ground truth. Reading it (`scripts/inject_chipkey.py`,
`tools/ufw-repack/jltech/chipkeybin.py`, `tools/jl-flash-decrypt/jl_sfc_decrypt.py`) establishes:

- The on-flash app area is scrambled with the chip's **eFuse "chipkey"** (per-device secret). The
  boot ROM descrambles with it and **rejects any image not scrambled with that exact key**.
- The **RCSP OTA path writes the code verbatim** (already chipkey-scrambled) — **no recrypt from a
  default key** on this path (unlike the USB-loader path), so the flashed image must carry *our*
  panel's chipkey.
- The chipkey is **not derivable** from PID/VID (random eFuse value; ElectronicCats hardcode each
  unit's — `0x9847`, `0xB165`), **not in the BLE `GET_TARGET_INFO`**, and we can't extract it from
  our OTA image because the vendor **serves no image for our board**. (For the sibling we *do* have,
  `TR2603R006`, its ENC key `0x1ce6` is effectively its chipkey — extractable only because that
  image was served.)
- ElectronicCats obtain the chipkey two ways, **both physical**: the USB loader
  (`jluboottool … → "Chip key: 0xXXXX"`) or a SPI-flash dump; their pipeline *starts* from a dump,
  which also yields the OEM uboot the repack must preserve byte-for-byte.

**Conclusion:** running custom firmware on the panel requires two per-device secrets — the eFuse
**chipkey** and the **OEM image** — obtainable only with physical access (SPI dump or USB loader).
With physical access ruled out, there is **no remote path** to custom firmware on this device, even
though the OTA channel and auth are fully solved. Reversing `TR2603`'s compressed code to read its
LED driver is possible but moot: the result still couldn't be flashed without the chipkey.

The only remaining way to put "XPRS on this panel" without physical access is the host-driven
display (an XPRS-capable device drives the panel over the reverse-engineered iPixel protocol) —
which is a different architecture than "the device itself receives".

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
