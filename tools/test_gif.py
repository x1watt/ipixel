import asyncio, sys, os, io
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from PIL import Image, ImageDraw
from ipixel import IPixel
def make_gif(w=16, h=16):
    frames = []
    for c in [(255, 0, 0), (0, 255, 0)]:
        im = Image.new("RGB", (w, h), c)
        ImageDraw.Draw(im).rectangle([2, 2, w - 3, h - 3], outline=(0, 0, 255))
        frames.append(im)
    b = io.BytesIO(); frames[0].save(b, "GIF", save_all=True, append_images=frames[1:], duration=500, loop=0)
    return b.getvalue()
async def main():
    g = make_gif(); print("gif bytes", len(g))
    async with IPixel(sys.argv[1]) as d:
        await d.handshake()
        await d.diy_mode(0)
        print(await d.upload_gif(g, slot=1, save=False))
asyncio.run(main())
