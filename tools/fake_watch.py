"""Gibt den Windows-PC als BLE-Geraet mit Akku-Dienst (0x180F) aus, zum Testen der iPhone-App ohne Uhr.

Der Wert steht in der Datei level.txt (0 bis 100) neben diesem Skript und wird alle 2 Sekunden
neu gelesen. Aenderungen werden an verbundene Geraete gemeldet.

Voraussetzung: pip install winrt-runtime winrt-Windows.Foundation winrt-Windows.Foundation.Collections
  winrt-Windows.Devices.Bluetooth winrt-Windows.Devices.Bluetooth.GenericAttributeProfile
  winrt-Windows.Storage.Streams
Start: python fake_watch.py [startwert] [--secure]
  --secure verlangt verschluesselte Verbindung, dann koppelt das iPhone das Geraet.
"""
import asyncio
import pathlib
import sys
import uuid

from winrt.windows.devices.bluetooth.genericattributeprofile import (
    GattCharacteristicProperties,
    GattLocalCharacteristicParameters,
    GattProtectionLevel,
    GattServiceProvider,
    GattServiceProviderAdvertisingParameters,
)
from winrt.windows.storage.streams import DataWriter

SERVICE = uuid.UUID("0000180f-0000-1000-8000-00805f9b34fb")
LEVEL = uuid.UUID("00002a19-0000-1000-8000-00805f9b34fb")
LEVEL_FILE = pathlib.Path(__file__).with_name("level.txt")

args = [a for a in sys.argv[1:] if not a.startswith("--")]
SECURE = "--secure" in sys.argv
level = int(args[0]) if args else 77


def buf(value: int):
    w = DataWriter()
    w.write_byte(value)
    return w.detach_buffer()


async def main():
    global level
    loop = asyncio.get_running_loop()

    res = await GattServiceProvider.create_async(SERVICE)
    if res.error != 0:
        raise SystemExit(f"Dienst konnte nicht erstellt werden: {res.error}")
    provider = res.service_provider

    params = GattLocalCharacteristicParameters()
    params.characteristic_properties = (
        GattCharacteristicProperties.READ | GattCharacteristicProperties.NOTIFY
    )
    params.read_protection_level = (
        GattProtectionLevel.ENCRYPTION_REQUIRED if SECURE else GattProtectionLevel.PLAIN
    )
    cres = await provider.service.create_characteristic_async(LEVEL, params)
    if cres.error != 0:
        raise SystemExit(f"Merkmal konnte nicht erstellt werden: {cres.error}")
    ch = cres.characteristic

    def on_read(sender, args):
        deferral = args.get_deferral()

        async def answer():
            req = await args.get_request_async()
            req.respond_with_value(buf(level))
            deferral.complete()
            print(f"gelesen: {level} %", flush=True)

        loop.call_soon_threadsafe(lambda: asyncio.ensure_future(answer()))

    ch.add_read_requested(on_read)
    ch.add_subscribed_clients_changed(
        lambda s, a: print(f"Abonnenten: {len(s.subscribed_clients)}", flush=True)
    )

    adv = GattServiceProviderAdvertisingParameters()
    adv.is_connectable = True
    adv.is_discoverable = True
    provider.start_advertising(adv)
    print(f"Werbe-Modus an, Wert {level} %. Datei: {LEVEL_FILE}", flush=True)

    LEVEL_FILE.write_text(str(level))
    while True:
        await asyncio.sleep(2)
        try:
            new = max(0, min(100, int(LEVEL_FILE.read_text().strip())))
        except Exception:
            continue
        if new != level:
            level = new
            print(f"neuer Wert: {level} %", flush=True)
            await ch.notify_value_async(buf(level))


asyncio.run(main())
