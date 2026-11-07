#!/usr/bin/env python3
"""Parse and extract a JieLi AC695x/BR22 .ufw firmware container.

Format (reverse-engineered from TR2603R006-01.ufw, an iPixel/Heaton vendor image):

  [0x000000]            payload blob: all partition images concatenated, each starting
                        at its directory `offset` (file-relative). AC695x payloads are
                        encrypted (entropy ~7.99); the key is chip-side, not in the app.
  [directory]           array of 32-byte entries, one per partition:
                          off  len  field
                           0    4   checksum (JieLi custom cd03_crc_encode, not CRC32/16)
                           4    4   offset into the file, little-endian
                           8    4   size in bytes, little-endian
                          12    1   type: 0x41 = normal OTA image, 0x01 = local-only stub
                          13    1   zero
                          14    1   partition index
                          15    1   zero
                          16   16   name, NUL-padded (e.g. "ble_app_ota.bin")
  [tail]                 ~32-byte signature footer (SHA-256-shaped) + "JLUFW" magic
                         (0x4a4c554657) at EOF-16, zero-padded to the end.

The directory base isn't pointed to by a header we parse; we locate it by scanning for the
first entry whose name is a known partition and whose offset+size chain is contiguous.

  python3 -I tools/ufw_parse.py firmware/TR2603R006-01.ufw [--extract OUTDIR]
"""
import math
import os
import struct
import sys
from collections import Counter

KNOWN = {b"ble_app_ota.bin", b"ble_ota.bin", b"edr_ota2.bin", b"nor_ota.bin",
         b"dev_nor_ota.bin", b"lcflash_ota.bin", b"uart_update.bin", b"uart_user.bin",
         b"sd_update2.bin", b"usb_update2.bin", b"cfg_tool.bin"}
MAGIC = b"JLUFW"


def entropy(s: bytes) -> float:
    if not s:
        return 0.0
    c = Counter(s)
    m = len(s)
    return -sum((v / m) * math.log2(v / m) for v in c.values())


def find_directory(b: bytes) -> int:
    """Return the file offset of the first 32-byte directory entry."""
    for i in range(0, len(b) - 32, 4):
        name = b[i + 16:i + 32].split(b"\0")[0]
        if name in KNOWN:
            _, off, size = struct.unpack_from("<III", b, i)
            if 0 < off < len(b) and 0 < size <= len(b) - off:
                return i
    raise SystemExit("no JieLi directory found (not a recognised .ufw?)")


def parse(path: str, outdir: str | None) -> None:
    b = open(path, "rb").read()
    assert b[-16:-11] == MAGIC or MAGIC in b[-32:], "missing JLUFW trailer magic"
    base = find_directory(b)
    print(f"{path}: {len(b)} bytes, directory @ 0x{base:06x}, JLUFW trailer present")
    print(f"{'idx':>3} {'name':18} {'offset':>9} {'size':>8} {'type':>4}  entropy")
    k = 0
    while True:
        e = b[base + k * 32:base + k * 32 + 32]
        if len(e) < 32:
            break
        name = e[16:32].split(b"\0")[0]
        if name not in KNOWN:
            break
        chk, off, size = struct.unpack_from("<III", e, 0)
        typ, idx = e[12], e[14]
        data = b[off:off + size]
        print(f"{idx:3d} {name.decode():18} {off:9d} {size:8d}  0x{typ:02x}  {entropy(data):6.3f}")
        if outdir:
            os.makedirs(outdir, exist_ok=True)
            open(os.path.join(outdir, name.decode()), "wb").write(data)
        k += 1
    if outdir:
        print(f"extracted {k} partitions to {outdir}/ (payloads remain chip-encrypted)")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    outdir = None
    if "--extract" in sys.argv:
        i = sys.argv.index("--extract")
        outdir = sys.argv[i + 1]
    parse(sys.argv[1], outdir)


if __name__ == "__main__":
    main()
