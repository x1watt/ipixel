"""Visual protocol test for a 64x16 panel. Watch the display while it runs."""
import asyncio, sys, os, io
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from PIL import Image, ImageDraw
from ipixel import IPixel
W, H = 64, 16
def gif():
    frames = []
    for c in [(255, 0, 0), (0, 255, 0)]:
        im = Image.new("RGB", (W, H), c)
        ImageDraw.Draw(im).rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 255))
        frames.append(im)
    b = io.BytesIO(); frames[0].save(b, "GIF", save_all=True, append_images=frames[1:], duration=500, loop=0)
    return b.getvalue()
def thirds():  # left red | middle green | right blue
    out = bytearray()
    for y in range(H):
        for x in range(W):
            out += bytes([(255, 0, 0), (0, 255, 0), (0, 0, 255)][min(2, x * 3 // W)])
    return bytes(out)
async def main():
    async with IPixel(sys.argv[1]) as d:
        await d.handshake()
        print("\n[1] DIY mode: clear + yellow diagonal-ish line (x=0..15,y=x) + white dot at (63,0)")
        await d.diy_mode(1)
        await d.draw_pixels((255, 255, 0), [(i, i) for i in range(16)])
        await d.draw_pixels((255, 255, 255), [(63, 0)])
        await asyncio.sleep(6)
        print("\n[2] live RGB frame: red | green | blue thirds")
        print(await d.show_rgb(thirds()))
        await asyncio.sleep(6)
        print("\n[3] GIF: red/green blinking with blue border")
        await d.diy_mode(0)
        print(await d.upload_gif(gif(), save=False))
asyncio.run(main())
