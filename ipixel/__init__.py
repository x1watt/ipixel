"""Minimal BLE client for iPixel Color LED displays (LED_BLE_xxxxxxxx).

Protocol reverse-engineered from the Android app com.wifiled.ipixels v3.8.1.
See docs/ble-protocol.md.
"""
import asyncio
import datetime
import struct

from bleak import BleakClient, BleakScanner

SERVICE_UUID = "000000fa-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000fa02-0000-1000-8000-00805f9b34fb"
NOTIFY_UUID = "0000fa03-0000-1000-8000-00805f9b34fb"
MANUFACTURER_ID = 0x5452  # bytes "TR" on air (bleak reports it little-endian as 0x5254)


def frame(cmd: int, payload: bytes = b"") -> bytes:
    """[u16 LE total length][u16 LE command][payload]."""
    return struct.pack("<HH", 4 + len(payload), cmd) + bytes(payload)


def parse_adv(mfr: bytes) -> dict:
    """Decode the manufacturer-data payload (after the 2-byte company id)."""
    d = {}
    if len(mfr) > 4:
        d["cid"] = f"{mfr[2]}{mfr[3]}".zfill(4)[-4:]
        d["pid"] = str(mfr[4]).zfill(3 if mfr[4] >= 100 else 2)
    if len(mfr) > 5:
        d["around"] = mfr[5]
    if len(mfr) > 6:
        d["size"] = mfr[6]
    return d


async def find_displays(timeout: float = 6.0):
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    out = []
    for addr, (dev, adv) in found.items():
        name = adv.local_name or dev.name or ""
        mfr = adv.manufacturer_data.get(0x5254)
        if "LED_BLE" in name or (mfr and len(mfr) > 1 and mfr[1] == 0x72):
            out.append((addr, name, adv.rssi, parse_adv(mfr) if mfr else {}))
    return out


class IPixel:
    def __init__(self, address: str, verbose: bool = True):
        self.address = address
        self.verbose = verbose
        self.client = BleakClient(address, timeout=20)
        self.rx: asyncio.Queue = asyncio.Queue()

    def _on_notify(self, _char, data: bytearray):
        if self.verbose:
            print("  <-", bytes(data).hex(" "))
        self.rx.put_nowait(bytes(data))

    async def __aenter__(self):
        await self.client.connect()
        try:  # BlueZ: ask for the negotiated ATT MTU (the app requests 512)
            await self.client._backend._acquire_mtu()
        except Exception:
            pass
        await self.client.start_notify(NOTIFY_UUID, self._on_notify)
        return self

    async def __aexit__(self, *exc):
        try:
            await self.client.disconnect()
        except Exception:
            pass

    async def send(self, data: bytes, wait: float = 1.0, response: bool = True):
        """Write one packet; return the list of notifications received within `wait` s."""
        while not self.rx.empty():
            self.rx.get_nowait()
        if self.verbose:
            print("  ->", data.hex(" "))
        await self.client.write_gatt_char(WRITE_UUID, data, response=response)
        replies = []
        try:
            while True:
                replies.append(await asyncio.wait_for(self.rx.get(), wait))
        except asyncio.TimeoutError:
            pass
        return replies

    # ---- simple commands -------------------------------------------------
    async def handshake(self, language: int = 0):
        """0x8001 'getLedType': sends wall-clock time, replies with panel info."""
        t = datetime.datetime.now()
        return await self.send(frame(0x8001, bytes([t.hour, t.minute, t.second, language])))

    async def hw_info(self):
        return await self.send(frame(0x8005))

    async def brightness(self, level: int):          # 0..100
        return await self.send(frame(0x8004, bytes([level])))

    async def power(self, on: bool):
        return await self.send(frame(0x0107, bytes([1 if on else 0])))

    async def upside_down(self, flipped: bool):
        return await self.send(frame(0x8006, bytes([1 if flipped else 0])))


    async def clock_mode(self, style: int = 1, h24: bool = True, show_date: bool = False):
        """0x0106: built-in clock face (also syncs the date). Week: Mon=1..Sun=7."""
        t = datetime.datetime.now()
        return await self.send(frame(0x0106, bytes([style, 0 if h24 else 1, 1 if show_date else 0,
                                                   t.year - 2000, t.month, t.day, t.isoweekday()])))

    async def set_week(self):
        return await self.send(frame(0x8012, bytes([datetime.date.today().isoweekday()])))

    async def delete_all(self):
        """0x8003: erase all stored programs/slots."""
        return await self.send(frame(0x8003))

    async def delete_slots(self, slots):
        """0x0102: delete specific stored slots."""
        return await self.send(frame(0x0102, struct.pack("<H", len(slots)) + bytes(slots)))

    async def text_speed(self, speed: int):
        return await self.send(frame(0x0103, bytes([speed])))

    async def countdown(self, flag: int, minutes: int, seconds: int):
        return await self.send(frame(0x800D, bytes([flag, minutes, seconds])))

    async def stopwatch(self, flag: int):
        return await self.send(frame(0x8009, bytes([flag])))

    async def scoreboard(self, a: int, b: int):
        return await self.send(frame(0x800A, struct.pack("<HH", a, b)))

    # ---- bulk data -------------------------------------------------------
    fast_writes = False  # write-without-response for bulk data (much faster; acks still gate frames)

    async def _write_packet(self, pkt: bytes, unit: int = 0):
        """Split one logical packet into ATT writes (the app uses 509-byte pieces at MTU 512)."""
        if not unit:
            unit = max(20, min(509, (self.client.mtu_size or 23) - 3))
        for i in range(0, len(pkt), unit):
            await self.client.write_gatt_char(WRITE_UUID, pkt[i:i + unit], response=not self.fast_writes)

    async def _send_frames(self, cmd: int, data: bytes, frame_size: int, crc: bool,
                           flag: int = 0, slot: int = 0, wait: float = 5.0):
        """Send `data` split into frame_size blocks, waiting for the device ack after each."""
        import zlib
        total = len(data)
        crc32 = zlib.crc32(data) & 0xFFFFFFFF
        replies = []
        for n, off in enumerate(range(0, total, frame_size)):
            chunk = data[off:off + frame_size]
            option = 0 if n == 0 else 2
            hdr = struct.pack("<HHBI", 0, cmd, option, total)
            if crc:
                hdr += struct.pack("<IBB", crc32, flag, slot)
            pkt = struct.pack("<H", len(hdr) + len(chunk)) + hdr[2:] + chunk
            while not self.rx.empty():
                self.rx.get_nowait()
            if self.verbose:
                print(f"  -> frame {n} ({len(pkt)} B) hdr {pkt[:len(hdr)].hex(' ')}")
            await self._write_packet(pkt)
            try:
                r = await asyncio.wait_for(self.rx.get(), wait)
                replies.append(r)
            except asyncio.TimeoutError:
                replies.append(None)
                break
        return replies

    async def show_rgb(self, rgb: bytes):
        """Live frame (app TYPE_CAMERA, cmd 0x0000): raw RGB888, row-major, width*height*3 bytes."""
        return await self._send_frames(0x0000, rgb, 12288, crc=False)

    async def upload_gif(self, gif: bytes, slot: int = 1, save: bool = True, frame_size: int = 4096):
        """GIF file (app TYPE_GIF, cmd 0x0003). save=False -> slot byte 101 (show without storing)."""
        return await self._send_frames(0x0003, gif, frame_size, crc=True,
                                       flag=2, slot=slot if save else 101)

    # ---- DIY / drawing mode ---------------------------------------------
    DIY_QUIT_DISCARD, DIY_ENTER_CLEAR, DIY_QUIT_KEEP, DIY_ENTER_KEEP = 0, 1, 2, 3

    async def diy_mode(self, mode: int):
        """0x0104: 1=enter & clear, 3=enter keep, 0=quit (restore previous), 2=quit keep drawing."""
        return await self.send(frame(0x0104, bytes([mode])))

    async def draw_pixels(self, rgb, points, move_type: int = 0):
        """0x0105: [option=move_type][R G B][x y][x y]... in DIY mode."""
        payload = bytes(rgb) + bytes(v for xy in points for v in xy)
        return await self.send(struct.pack("<HHB", 5 + len(payload), 0x0105, move_type) + payload)

    # ---- text ------------------------------------------------------------
    async def send_text(self, text: str, color=(255, 255, 255), bg=None, effect: int = 1,
                        speed: int = 50, height: int = 16, font_path: str = None,
                        h_align: int = 0, v_align: int = 0, slot: int = 1, save: bool = True,
                        frame_size: int = 4096):
        """Text program (app TYPE_TEXT, cmd 0x0100). The host renders each glyph as a 1-bit bitmap."""
        data = encode_text(text, color, bg, effect, speed, height, font_path, h_align, v_align)
        return await self._send_frames(0x0100, data, frame_size, crc=True,
                                       flag=0, slot=slot if save else 101)


def pack_1bit(bits, width: int, height: int) -> bytes:
    """Row-major, each row padded to a multiple of 8 px, LSB = leftmost pixel (TextAgreement.getTextData)."""
    stride = (width + 7) // 8 * 8
    out = bytearray(stride * height // 8)
    for y in range(height):
        for x in range(width):
            if bits(x, y):
                i = y * stride + x
                out[i >> 3] |= 1 << (i & 7)
    return bytes(out)


def render_glyph(ch: str, height: int = 16, font_path: str = None):
    from PIL import Image, ImageDraw, ImageFont
    font_path = font_path or "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    try:
        font = ImageFont.truetype(font_path, height - 2)
    except OSError:
        font = ImageFont.load_default()
    w = max(1, int(round(font.getlength(ch)))) if ch != " " else height // 3
    im = Image.new("1", (w, height), 0)
    ImageDraw.Draw(im).text((0, height // 2), ch, fill=1, font=font, anchor="lm")
    return im


def encode_text(text, color=(255, 255, 255), bg=None, effect=1, speed=50, height=16,
                font_path=None, h_align=0, v_align=0) -> bytes:
    chars = [c for c in text.replace("\n", " ")]
    bgf, bgc = (0, (0, 0, 0)) if bg is None else (1, bg)
    head = struct.pack("<H", len(chars)) + bytes([h_align, v_align, effect, speed, 0, *color, bgf, *bgc])
    body = b""
    for ch in chars:
        im = render_glyph(ch, height, font_path)
        w, h = im.size
        body += bytes([0x80, *color, w, h]) + pack_1bit(lambda x, y: im.getpixel((x, y)), w, h)
    return head + body



# Handshake reply byte[4] -> (app LED type, width, height). From ChooseActivity.setLedType + AppConfig.ledSizeMap.
# Some codes map differently for specific CID/PID (see docs/ble-protocol.md).
PANEL_TYPES = {
    0x00: (0, 64, 64), 0x80: (0, 64, 64), 0x81: (2, 32, 32), 0x82: (4, 32, 16), 0x83: (3, 64, 16),
    0x84: (1, 96, 16), 0x85: (5, 64, 20), 0x86: (6, 128, 32), 0x87: (7, 144, 16), 0x88: (8, 192, 16),
    0x89: (9, 48, 24), 0x8A: (10, 64, 32), 0x8B: (11, 96, 32), 0x8C: (12, 128, 32), 0x8D: (13, 96, 32),
    0x8E: (14, 160, 32), 0x8F: (15, 192, 32), 0x90: (16, 256, 32), 0x91: (17, 320, 32), 0x92: (18, 384, 32),
    0x93: (19, 448, 32), 0x94: (20, 16, 16), 0x95: (24, 64, 64), 0x96: (25, 96, 64), 0x97: (26, 128, 64),
    0x98: (27, 160, 64), 0x99: (28, 192, 64), 0x9A: (29, 256, 64), 0x9B: (30, 320, 64), 0x9C: (31, 384, 64),
    0x9D: (32, 448, 64), 0x9E: (33, 512, 64), 0x9F: (34, 576, 64), 0xA0: (35, 640, 64),
}
# Frame size used to split uploads: 12288 for 64x64 (0x00/0x80) and 32x32 (0x81), 4096 otherwise.
BIG_FRAME_CODES = {0x00, 0x80, 0x81}


def panel_from_handshake(reply: bytes):
    """Return dict(code, led_type, width, height, frame_size, password) from a 0x8001 reply."""
    code = reply[4]
    led_type, w, h = PANEL_TYPES.get(code, (None, None, None))
    return {"code": code, "led_type": led_type, "width": w, "height": h,
            "frame_size": 12288 if code in BIG_FRAME_CODES else 4096,
            "password": bool(reply[10]) if len(reply) > 10 else False}


def image_to_rgb(path_or_img, width: int, height: int) -> bytes:
    from PIL import Image
    im = path_or_img if hasattr(path_or_img, "convert") else Image.open(path_or_img)
    return im.convert("RGB").resize((width, height)).tobytes()


def gif_for_panel(path: str, width: int, height: int) -> bytes:
    """Re-encode any image/GIF to the panel resolution, keeping animation timing."""
    import io
    from PIL import Image, ImageSequence
    src = Image.open(path)
    frames, durations = [], []
    for f in ImageSequence.Iterator(src):
        frames.append(f.convert("RGB").resize((width, height)))
        durations.append(f.info.get("duration", 100))
    b = io.BytesIO()
    frames[0].save(b, "GIF", save_all=True, append_images=frames[1:], duration=durations, loop=0)
    return b.getvalue()
