#!/usr/bin/env python3
"""Find and download an official iPixel Color firmware (.ufw/.bin) to inspect.

The user's own panel (ACT1033, fw 1402) reports no update, so this also sweeps the related
board codes from the app's two OTA request paths to fetch *any* image from the same family,
which reveals the JieLi .ufw format and chip. Nothing is sent to the panel.

  python3 -I tools/fetch_firmware.py             # sweep the R2305R021 family (+ neighbours)
  python3 -I tools/fetch_firmware.py 1402 0007 04  # one AES query for a specific build
"""
import base64
import hashlib
import json
import os
import random
import string
import sys
import time
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.padding import PKCS7

KEY = b"5uMoiJzoUCtI7KWl4U5yWWcFK6OEb6Nz"   # AESUtils.createCustomKey (from the user's own APK)
IV = b"0000000000000000"
URL = "https://manage.heaton.com.cn/api/rm/getFirmwareInfo"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "firmware")
UA = "okhttp/4.9.0"


def encode_to_url(s: str) -> str:
    e = urllib.parse.quote(s, safe="")
    return e.replace("%26", "&").replace("%3D", "=").replace("%3F", "?")


def sorted_join(params: dict) -> str:
    return "&".join(f"{k}={params[k]}" for k in sorted(params))


def aes_enc(plain: str) -> str:
    p = PKCS7(128).padder()
    data = p.update(plain.encode()) + p.finalize()
    c = Cipher(algorithms.AES(KEY), modes.CBC(IV)).encryptor()
    return base64.b64encode(c.update(data) + c.finalize()).decode()


def aes_dec(b64: str) -> str:
    c = Cipher(algorithms.AES(KEY), modes.CBC(IV)).decryptor()
    raw = c.update(base64.b64decode(b64)) + c.finalize()
    u = PKCS7(128).unpadder()
    return (u.update(raw) + u.finalize()).decode("utf-8", "replace")


def _post(url: str, data: bytes, headers: dict) -> str:
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, **headers})
    return urllib.request.urlopen(req, timeout=20).read().decode()


def aes_query(version: int, project_no: str) -> dict | None:
    """JieLi path (newFirmwareInfo): signed + AES body, AES reply."""
    rnd = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(8))
    ts = str(int(time.time()))
    params = {"appid": "137", "project_no": project_no, "version": str(version), "android_version": "3.8.1"}
    sign = hashlib.md5(encode_to_url(sorted_join(dict(params, random=rnd, timestamp=ts,
                       app_key=KEY.decode()))).encode()).hexdigest().lower()
    body = aes_enc(encode_to_url(sorted_join(params)))
    try:
        resp = _post(f"{URL}?sign={sign}&timestamp={ts}&random={rnd}", body.encode(),
                     {"Content-Type": "text/plain"})
        return json.loads(aes_dec(resp))
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def form_query(version: int, project_no: str) -> dict | None:
    """Custom path (firmwareInfo): plain form-encoded, plaintext JSON reply."""
    body = urllib.parse.urlencode({"appid": "137", "project_no": project_no,
                                   "version": str(version), "android_version": "3.8.1"})
    try:
        resp = _post(URL, body.encode(), {"Content-Type": "application/x-www-form-urlencoded"})
        return json.loads(resp)
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def file_path_of(reply: dict | None):
    if not reply:
        return None
    data = reply.get("data") or {}
    return data.get("file_path")


def download(fp: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, fp.split("/")[-1])
    # The image CDN 403s the default urllib UA; mimic the app's okhttp client.
    headers = {"User-Agent": UA, "Referer": "https://manage.heaton.com.cn/",
               "Accept": "*/*", "Connection": "keep-alive"}
    req = urllib.request.Request(fp, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r, open(out, "wb") as f:
        f.write(r.read())
    print("  SAVED", out, os.path.getsize(out), "bytes")


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        version = int(sys.argv[1])
        cid = sys.argv[2] if len(sys.argv) > 2 else "0007"
        pid = sys.argv[3] if len(sys.argv) > 3 else "04"
        base = {11: "R2305R021_11_", 14: "R2305R021_14_", 15: "R2305R021_15_"}.get(version // 100, "R2305R021_14_")
        r = aes_query(version, base + cid + pid)
        print(json.dumps(r, ensure_ascii=False))
        fp = file_path_of(r)
        if fp:
            print("file_path:", fp)
            download(fp)
        return

    # Sweep: (request fn, version, project_no). Low versions so the server offers the latest.
    # R2305R021 is our panel's board family; _08/_13 are generic (no cid/pid).
    cp = "000704"  # our cid+pid
    candidates = [
        (form_query, 801, "R2305R021_08"),
        (form_query, 1301, "R2305R021_13"),
        (form_query, 1001, "TR2304R009-10"),
        (form_query, 701, "TR2104R003-07"),
        (aes_query, 1101, "R2305R021_11_" + cp),
        (aes_query, 1501, "R2305R021_15_" + cp),
        (aes_query, 1401, "R2305R021_14_" + cp),
        # same generic board codes via the AES path too, in case routing differs server-side
        (aes_query, 1301, "R2305R021_13"),
        (aes_query, 801, "R2305R021_08"),
    ]
    got = []
    for fn, ver, pno in candidates:
        r = fn(ver, pno)
        msg = (r or {}).get("msg") or (r or {}).get("error") or ""
        fp = file_path_of(r)
        print(f"[{fn.__name__:10} v{ver:<5} {pno:24}] -> {fp or msg}")
        if fp:
            got.append(fp)
    uniq = sorted(set(got))
    for fp in uniq:
        print("downloading", fp)
        try:
            download(fp)
        except Exception as e:  # noqa: BLE001
            print("  download failed:", e)
    if not uniq:
        print("\nNo firmware offered for any of these codes. The only remaining route is a "
              "physical flash dump (needs the board opened).")


if __name__ == "__main__":
    main()
