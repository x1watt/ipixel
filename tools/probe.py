import asyncio, sys
sys.path.insert(0, __import__("os").path.dirname(__file__) + "/..")
from ipixel import IPixel, find_displays
async def main():
    addr = sys.argv[1] if len(sys.argv) > 1 else None
    if not addr:
        devs = await find_displays()
        print(devs); addr = devs[0][0]
    async with IPixel(addr) as d:
        print("handshake"); await d.handshake()
        print("hw_info"); await d.hw_info()
        for lvl in (10, 100, 50):
            print("brightness", lvl); await d.brightness(lvl); await asyncio.sleep(0.8)
asyncio.run(main())
