#!/usr/bin/env python3
"""Command line control for iPixel Color BLE LED displays.

  ipixel_cli.py scan
  ipixel_cli.py [-a ADDR] info
  ipixel_cli.py [-a ADDR] text "Hello" [--color ff0000] [--effect 1] [--speed 50]
  ipixel_cli.py [-a ADDR] gif file.gif         (any image/GIF, rescaled to the panel)
  ipixel_cli.py [-a ADDR] image file.png       (live frame, not stored)
  ipixel_cli.py [-a ADDR] brightness 0..100 | power on|off | flip on|off | clock [style]
"""
import argparse, asyncio, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import ipixel as ip


async def main(a):
    if a.cmd == "scan":
        for d in await ip.find_displays():
            print(*d)
        return
    addr = a.address
    if not addr:
        devs = await ip.find_displays()
        if not devs:
            sys.exit("no LED_BLE display found")
        addr = devs[0][0]
    async with ip.IPixel(addr, verbose=a.verbose) as d:
        r = await d.handshake()
        panel = ip.panel_from_handshake(r[0])
        W, H, FS = panel["width"], panel["height"], panel["frame_size"]
        if a.cmd == "info":
            print(addr, panel, "hw:", (await d.hw_info())[0].hex(" "))
        elif a.cmd == "text":
            c = bytes.fromhex(a.color)
            res = await d.send_text(a.args[0], color=tuple(c), effect=a.effect, speed=a.speed,
                                    height=H if H <= 32 else 32, save=a.save, frame_size=FS)
            print("ack", [x.hex(" ") if x else None for x in res])
        elif a.cmd == "gif":
            res = await d.upload_gif(ip.gif_for_panel(a.args[0], W, H), save=a.save, frame_size=FS)
            print("ack", [x.hex(" ") if x else None for x in res])
        elif a.cmd == "image":
            res = await d.show_rgb(ip.image_to_rgb(a.args[0], W, H))
            print("ack", [x.hex(" ") if x else None for x in res])
        elif a.cmd == "brightness":
            await d.brightness(int(a.args[0]))
        elif a.cmd == "power":
            await d.power(a.args[0] == "on")
        elif a.cmd == "flip":
            await d.upside_down(a.args[0] == "on")
        elif a.cmd == "clock":
            await d.clock_mode(int(a.args[0]) if a.args else 1)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-a", "--address")
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("--color", default="ffffff")
    p.add_argument("--effect", type=int, default=1)
    p.add_argument("--speed", type=int, default=50)
    p.add_argument("--save", action="store_true", help="store in a slot instead of showing temporarily")
    p.add_argument("cmd")
    p.add_argument("args", nargs="*")
    asyncio.run(main(p.parse_args()))
