import asyncio, sys, os
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from ipixel import IPixel
W = H = 16
def pattern():
    out = bytearray()
    for y in range(H):
        for x in range(W):
            out += bytes([255, 0, 0]) if x < 8 else bytes([0, 0, 255])
    return bytes(out)
async def main():
    async with IPixel(sys.argv[1]) as d:
        print("mtu", d.client.mtu_size)
        await d.handshake()
        print("enter DIY"); await d.diy_mode(1)
        print("diagonal green"); await d.draw_pixels((0, 255, 0), [(i, i) for i in range(16)])
        await asyncio.sleep(3)
        print("live RGB frame (red|blue)"); print(await d.show_rgb(pattern()))
        await asyncio.sleep(3)
asyncio.run(main())
