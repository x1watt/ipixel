import asyncio, sys, os, time
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from ipixel import IPixel
W, H = 64, 16
async def main():
    async with IPixel(sys.argv[1], verbose=False) as d:
        d.fast_writes = len(sys.argv) > 2
        await d.handshake()
        await d.diy_mode(1)
        n, ok, t0 = 0, 0, time.time()
        while time.time() - t0 < 10:
            c = [(255,0,0),(0,255,0),(0,0,255)][n % 3]
            r = await d.show_rgb(bytes(c) * (W * H))
            ok += r and r[0] and r[0][4] == 1
            n += 1
        dt = time.time() - t0
        print(f"{n} frames in {dt:.1f}s = {n/dt:.1f} fps, acked ok {ok}")
asyncio.run(main())
