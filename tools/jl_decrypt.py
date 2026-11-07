#!/usr/bin/env python3
"""Recover the JieLi ENC root key of a firmware partition and decrypt it.

JieLi's "ENC" scrambler is an LFSR stream cipher (CRC16-CCITT taps, poly 0x1021,
one shift per byte) XORed over the data. In the iPixel AC695x images it runs as a
single continuous stream over each partition, seeded once with a 16-bit root key:

    out[i] = cipher[i] ^ (key & 0xFF)
    key    = (key << 1) ^ (0x1021 if key & 0x8000 else 0)      # advance one step

The root key is only 16 bits, so we brute all 65536 seeds and pick the one whose
decrypt looks least random (most zero bytes / lowest entropy). Compressed code stays
high-entropy even when correctly decrypted, but string tables and zero runs confirm
the key. (ble_app_ota.bin of TR2603R006-01.ufw -> key 0x1ce6.)

    python3 -I tools/jl_decrypt.py firmware/extracted/ble_app_ota.bin [--key 0x1ce6] [-o out.bin]
"""
import sys
import math
from collections import Counter

try:
    import numpy as np
except ImportError:
    np = None


def entropy(b: bytes) -> float:
    if not b:
        return 0.0
    c = Counter(b)
    n = len(b)
    return -sum((v / n) * math.log2(v / n) for v in c.values())


def decrypt(data: bytes, key: int) -> bytes:
    out = bytearray(len(data))
    s = key & 0xFFFF
    for i, b in enumerate(data):
        out[i] = b ^ (s & 0xFF)
        s = ((s << 1) & 0xFFFF) ^ (0x1021 if s & 0x8000 else 0)
    return bytes(out)


def crack(data: bytes, scan: int = 8192):
    """Return (best_key, entropy) by brute-forcing the 16-bit seed over the first `scan` bytes."""
    n = min(scan, len(data))
    if np is not None:
        raw = np.frombuffer(data[:n], dtype=np.uint8)
        state = np.arange(65536, dtype=np.uint32)
        dec = np.zeros((65536, n), dtype=np.uint8)
        for i in range(n):
            dec[:, i] = raw[i] ^ (state & 0xFF).astype(np.uint8)
            state = ((state << 1) & 0xFFFF) ^ (((state >> 15) & 1) * 0x1021)
        zeros = (dec == 0).sum(axis=1)
        cand = np.argsort(-zeros)[:16]
        best = min(((int(k), entropy(bytes(dec[k]))) for k in cand), key=lambda t: t[1])
        return best
    # pure-python fallback (slower)
    best = (0, 9.0)
    for k in range(65536):
        h = entropy(decrypt(data[:n], k))
        if h < best[1]:
            best = (k, h)
    return best


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    path = args[0]
    key = None
    out = None
    if "--key" in args:
        key = int(args[args.index("--key") + 1], 0)
    if "-o" in args:
        out = args[args.index("-o") + 1]
    data = open(path, "rb").read()
    if key is None:
        key, h = crack(data)
        print(f"{path}: recovered key 0x{key:04x} (head entropy {h:.3f}, raw {entropy(data[:8192]):.3f})")
    dec = decrypt(data, key)
    print(f"  full entropy {entropy(dec):.3f}; per-4KB:",
          " ".join("%.1f" % entropy(dec[o:o + 4096]) for o in range(0, len(dec), 4096)))
    import re
    strs = [s.decode() for s in re.findall(rb"[\x20-\x7e]{5,}", dec)]
    good = [s for s in strs if sum(c.isalnum() or c in "_./- " for c in s) >= len(s) * 0.8]
    print(f"  {len(strs)} printable runs, {len(good)} identifier-like:")
    for s in good[:50]:
        print("    ", s)
    if out:
        open(out, "wb").write(dec)
        print("  wrote", out)


if __name__ == "__main__":
    main()
