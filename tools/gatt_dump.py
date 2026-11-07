import asyncio, sys
from bleak import BleakClient
ADDR = sys.argv[1] if len(sys.argv) > 1 else "C3:EF:3E:4F:7E:B7"
async def main():
    async with BleakClient(ADDR, timeout=20) as c:
        print("connected, mtu", c.mtu_size)
        for s in c.services:
            print("SERVICE", s.uuid)
            for ch in s.characteristics:
                print("   CHAR", ch.uuid, ch.properties, "handle", ch.handle)
asyncio.run(main())
