import asyncio, sys, os
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from ipixel import IPixel
async def main():
    async with IPixel(sys.argv[1]) as d:
        await d.handshake()
        print(await d.send_text(sys.argv[2] if len(sys.argv) > 2 else "Hello Linux!", color=(0, 200, 255), effect=int(sys.argv[3]) if len(sys.argv) > 3 else 1, save=False))
asyncio.run(main())
