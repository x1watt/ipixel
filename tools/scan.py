import asyncio
from bleak import BleakScanner
async def main():
    found = await BleakScanner.discover(timeout=8, return_adv=True)
    for addr, (dev, adv) in found.items():
        print(addr, repr(adv.local_name), adv.rssi, adv.service_uuids, {k: v.hex() for k, v in adv.manufacturer_data.items()})
asyncio.run(main())
