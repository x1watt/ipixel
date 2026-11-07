# Firmware / OTA notes — ACT1033 (and relatives)

Analysis only. **Nothing here has been sent to the panel.** This documents how the official
iPixel Color app updates firmware, so we can assess whether custom firmware is realistic. Derived
from the decompiled app (v3.8.1) and corroborated by public research (see end).

## 1. Which panel, which chip

The test unit identifies itself as **"Funscreen – ACT1033"**: the app maps the advertised
CID `0007` / PID `04` to that product name (`ui/adapter/NewConnectAdapter.java`). ACT1025 is
CID `0007`/PID `01`.

- **SoC: JieLi AC695x / "BR22" family** (Zhuhai Jieli, 杰理). The app ships `libjl_ota_auth.so`
  and the panel exposes JieLi's RCSP OTA GATT service `0xAE00` (write `AE01`, notify `AE02`).
  The family is now confirmed directly from a real vendor `.ufw` (see §2.2): its plaintext strings
  include `AC695x_update`, `695X_LE_UPDATE`, `JL-BR22`, `br22xx`, `JLBTSDK`. Community projects
  report the specific die as **AC6951C**, which is a member of this exact AC695x/BR22 family — so
  that is almost certainly ours too. The precise die/suffix still can't be read over BLE; a PCB
  photo would pin the exact part, but the SDK family is no longer in doubt.
- **Firmware version** comes from the `0x8005` "hardware info" reply. Ours was
  `08 00 05 80 0e 02 07 04` →
  - `mcu = 0x0e = 14`
  - `version = "14" ‖ "02" = 1402`
  - display string = `7.04` (meaning of the last two bytes unconfirmed)
- **Routing by version** (`ui/ChooseActivity`): 1100–2799 or ≥5200 → **JieLi path**; 200–1399 and
  2800–4600 → the vendor's own OTA protocol. **1402 ⇒ JieLi path.**

## 2. Where official firmware comes from

The app does **not** bundle any firmware (no `.bin`/`.ufw`/`.bfu` in the APK). It fetches it:

- `POST https://manage.heaton.com.cn/api/rm/getFirmwareInfo`
- JieLi path sends an **AES-256-CBC** (PKCS7) encrypted, signed body; the key and IV are embedded
  in the APK (`baselib/retrofit/AESUtils.java`, `…/CryptographicParsingToolKt.java`). They are not
  reproduced here — extract them from your own APK if you need to query the server. `sign` is an
  MD5 over the sorted params + random + timestamp + app key.
- Params: `appid=137`, `project_no`, `version`, `android_version`. For 14xx firmware,
  `project_no = "R2305R021_14_" + cid + pid`.
- Response JSON (`OTAInformation`): `file_path` (firmware URL, must contain `.ufw`), `version_no`,
  `need_update`, `force`, `desc_cn`/`desc_en`. **No hash/MD5 field.** The `.ufw` is downloaded with a
  plain GET and flashed from memory.

### 2.1 What the server actually returns (verified 2026-11-07)

`tools/fetch_firmware.py` was run against the live endpoint (keys/IV from our own APK). Results:

- **Our board** (`R2305R021_14_000704`, also `_11`/`_15`, AES path) → `请求失败,查无数据`
  ("no data"). The 1402 firmware is the latest; **no OTA image is published for it.**
- **Sibling boards** (vendor/form path, versions 8/13) **do** return images, e.g.
  `R2305R021_08` → `…/TR2305R021_08_05_ota_mi.bin`, `R2305R021_13` →
  `…/TR2310R004_13_03_ota_mi.bin`, `TR2304R009-10`, `TR2104R003-07`. Four were downloaded
  (182–371 KB) into `firmware/` (gitignored). The image CDN (`images.heaton.com.cn`) 403s
  unless the request carries the app's `okhttp` User-Agent + a `manage.heaton.com.cn` Referer.

**These are NOT our chip's images.** Analysis of the four:
- No `JLUFW` marker → **not** the JieLi `.ufw` format. They are the vendor's own OTA format,
  matching the 200–1399 (non-JieLi) routing range — a *different* MCU family from our 1402 panel.
- Byte-identical from offset 4 to ≥255 across all four; they differ only at offsets 2–3. So the
  first word is magic `8C D4` + a per-image checksum at `[2:4]`, followed by a shared
  vector-table/bootloader stub ⇒ these four panels share one MCU + bootloader.
- Entropy ~6.2–6.5 bits/byte with long constant-byte runs (`0x3f`, `0xd4`) ⇒ a light byte-level
  scramble, **not** encryption; but no plaintext chip id survives, so they don't name the die.

**Bottom line:** the firmware server cannot shortcut chip identification for the ACT1033 — the one
image that matches it isn't served, and the images that are served are a different, obfuscated MCU
family. Community RE reports the iPixel panels use a **JieLi AC6951C** MCU with a **ZBIT ZB25VQ32**
SPI flash, consistent with our JieLi-path evidence, but the exact part is not broadcast over BLE or
in any served image. Confirming *our* die still requires a PCB photo or an SPI-flash dump.

### 2.2 A real JieLi `.ufw`, dissected (obtained 2026-11-08)

`tools/fetch_firmware.py jieli` sweeps every JieLi board family (from `JLOTA.checkOTA`) across the
`cid`/`pid` pairs the app references. Our own family (`R2305R021_14/_15/_11_000704`) returns no
image, but one sibling does: **`TR2403R015_21` / cid `0001` pid `13` → `TR2603R006-01.ufw`**
(v2117, dated 2026-03-24, 1 454 944 B, saved to `firmware/`). Same JieLi OTA path and chip family
as our panel, so it is representative of what an ACT1033 image looks like.

Structure:
- **Container, not a flat image.** Overall entropy 7.94 (body sections are compressed/encrypted),
  but it is a JieLi multi-partition container with plaintext headers between sections and large raw
  `0xFF` gaps. The chip/SDK strings above sit in the clear.
- **Partition images inside** (JieLi AC695x OTA set): `uboot.*`, `ble_app_ota.bin`, `ble_ota.bin`,
  `edr_ota2.bin`, `nor_ota.bin`, `dev_nor_ota.bin`, `lcflash_ota.bin`, `cfg_tool.bin`, plus the
  transport stubs `uart_update.bin` / `usb_update2.bin` / `sd_update2.bin` and the handlers
  `user_norflash_ufw_update` / `user_lc_flash_ufw_update` / `UPDATE_JUMP`.
- **`JLUFW` is a trailer magic**, not a header: at offset `len-16` (`4a4c554657`), zero-padded to
  the end. Immediately before it is a 32-byte block (shape of a SHA-256 digest) preceded by another
  ~32-byte block — consistent with a signature/hash footer that the bootloader checks.
- Decrypting the compressed/encrypted partitions needs JieLi's per-file key/scheme from
  `libjl_ota_auth.so` (the §3 auth blocker); it is not needed just to identify the chip/format.

Net: the firmware route has now delivered everything it can without touching hardware — chip family
(**AC695x/BR22**) and the exact `.ufw` layout are known. What remains (per-file key, exact die,
flash readback, recovery pads) is gated on physical access, unchanged from §4.

## 3. The JieLi RCSP OTA path (what applies to us)

- SDK: `com.jieli.jl_bt_ota` **v1.10.0**, wrapped by `com.tiro.jlotalibrary`.
- Config used by the app: `useAuthDevice=true`, `bleInterval=500ms`, `timeout=3000ms`,
  `needChangeMtu=false`, `useReconnect=true`, `firmwareFileData=<downloaded .ufw>`.
- **Firmware format:** `.ufw` (the auth lib contains the marker `JLUFW`; parsing is native,
  `ParseDataUtil.nativeFilterFile`).
- **Auth** (`RcspAuth`, native in `libjl_ota_auth.so`): a challenge/response. 17-byte packets
  (`00`/`01` + 16 bytes), 5-byte `02…` status, success = `02 "pass"`. The strings
  `function_E1test`, `function_E21`, `function_xiaomi`, `cd03_crc_encode`, `CRC16`, `parse_fw_info`
  suggest the known JieLi E1/E21 auth family. The algorithm/key is **not** in plain strings; it
  would need disassembly. `setUseAuthDevice(false)` exists in the SDK but only works if the
  firmware permits it.

The vendor's **own** OTA protocol (for other MCUs, over `0x00FA`) is also documented in
`docs/ble-protocol.md §8` region, but it does not apply to the 1402 firmware.

## 4. Can we write custom firmware? Go/no-go

**Feasible in principle, not yet actionable — and risky.** Blockers, in order:

1. **No firmware dump.** JieLi OTA cannot read the existing image back out (confirmed by Quarkslab
   on a sibling JieLi device). Without the stock `.ufw` we can't study the exact flash layout, LED
   driver or pin map — and can't restore it.
2. **Unknown exact chip.** Needs a PCB photo. The open JieLi SDK targets the AC63 family; ours may
   differ enough to require porting.
3. **Signed/authenticated OTA.** Building a `.ufw` the bootloader accepts means matching JieLi's
   image format and, likely, the auth/signing. Community tooling exists for *other* JieLi parts
   (Electronic Cats badge) but not for this panel.
4. **Brick risk.** A bad flash with no readback almost certainly needs physical recovery
   (USB-ISP/UART on the board). `iPixel-CLI` warns bad BLE data alone can bootloop.

### Recommended sequence

- **Now (safe, BLE-only / offline):** this document. Optionally, query `getFirmwareInfo` for
  `R2305R021_14_000704` to get the official `.ufw` as a study baseline. No writes to the panel.
- **Next (your hands):** open the case, photograph the SoC + SPI-flash markings. This confirms the
  die and whether the open SDK applies.
- **Later (only with brick risk accepted):** identify the board's recovery pads first; then either
  build from `Jieli-Tech/fw-AC63_BT_SDK` or adapt `ElectronicCats/jieli-ble-badge-research`'s
  `.ufw` toolchain. Keep the stock `.ufw` from step 1 as the recovery image.

The pragmatic alternative, which already beats the stock firmware's features, is what this repo
does: render on the host and stream live frames (~9 fps). Custom firmware mainly buys standalone
operation without a host.

## 5. References

- Quarkslab, "A modern tale of blinkenlights" — JieLi OTA auth reversed; OTA can't dump firmware.
- `ElectronicCats/jieli-ble-badge-research` — self-built `.ufw` on a JieLi AC707N/BR35 over BLE.
- `Jieli-Tech/fw-AC63_BT_SDK`, `Jieli-Tech/iOS-JL_OTA` — official SDK + OTA.
- `lucagoc/iPixel-CFW` — early custom-firmware attempt for these panels.
- `lucagoc/pypixelcolor`, `cagcoach/ha-ipixel-color`, `yewolf` LED-matrix write-up — protocol RE.
