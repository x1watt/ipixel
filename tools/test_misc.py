import asyncio, sys, os
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from ipixel import IPixel
async def main():
    async with IPixel(sys.argv[1]) as d:
        await d.handshake()
        print("[1] clock style 1, 24h"); await d.clock_mode(1, True, False); await asyncio.sleep(6)
        print("[2] power off 4s");        await d.power(False); await asyncio.sleep(4)
        print("[3] power on");            await d.power(True); await asyncio.sleep(2)
        print("[4] upside down 5s");      await d.upside_down(True); await asyncio.sleep(5)
        print("[5] normal");              await d.upside_down(False)
asyncio.run(main())
