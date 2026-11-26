"""Meldet dem iPhone einen Akkustand wie ein Bluetooth-Headset (Freisprech-Profil mit Apple-Zusatzbefehl).

Das Geraet muss vorher mit dem iPhone gekoppelt sein (Windows: Einstellungen, Bluetooth und Geraete,
Geraet hinzufuegen, Bluetooth, iPhone waehlen und am iPhone bestaetigen).

Der Wert steht in level.txt (0 bis 100) neben diesem Skript und wird alle 2 Sekunden gelesen.

Start: python hfp_battery.py [namensteil]    (Standard: iPhone)

Ablauf wie bei einem Headset:
  AT+BRSF, AT+CIND=?, AT+CIND?, AT+CMER, dann AT+XAPL (Apple, Batterie-Funktion)
  und AT+IPHONEACCEV=1,1,<0..9> fuer den Akkustand.
"""
import asyncio
import pathlib
import sys
import uuid

from winrt.windows.devices.bluetooth import BluetoothDevice
from winrt.windows.devices.bluetooth.rfcomm import RfcommDeviceService, RfcommServiceId
from winrt.windows.devices.enumeration import DeviceInformation
from winrt.windows.networking.sockets import StreamSocket
from winrt.windows.storage.streams import DataReader, DataWriter, InputStreamOptions

HFP_AG = uuid.UUID("0000111f-0000-1000-8000-00805f9b34fb")
LEVEL_FILE = pathlib.Path(__file__).with_name("level.txt")
NAME_PART = (sys.argv[1] if len(sys.argv) > 1 else "iPhone").lower()


async def find_phone():
    sel = BluetoothDevice.get_device_selector_from_pairing_state(True)
    for d in await DeviceInformation.find_all_async_aqs_filter(sel):
        print("gekoppelt:", d.name)
        if NAME_PART in d.name.lower():
            return await BluetoothDevice.from_id_async(d.id)
    return None


class At:
    def __init__(self, sock):
        self.w = DataWriter(sock.output_stream)
        self.r = DataReader(sock.input_stream)
        self.r.input_stream_options = InputStreamOptions.PARTIAL
        self.pending = None

    async def send(self, cmd: str):
        print(">>", cmd, flush=True)
        self.w.write_string(cmd + "\r")
        await self.w.store_async()

    async def read(self, until_ok=True, timeout=6.0) -> str:
        """Liest, bis OK oder ERROR kommt (oder Zeit ablaeuft). Ein laufendes Lesen wird nie abgebrochen."""
        out = ""
        loop = asyncio.get_running_loop()
        end = loop.time() + timeout
        while loop.time() < end:
            if self.pending is None:
                self.pending = asyncio.ensure_future(self.r.load_async(512))
            done, _ = await asyncio.wait({self.pending}, timeout=min(1.5, max(0.1, end - loop.time())))
            if not done:
                if not until_ok:
                    break
                continue
            n = self.pending.result()
            self.pending = None
            if n == 0:
                raise ConnectionError("iPhone hat die Verbindung getrennt")
            out += self.r.read_string(n)
            if until_ok and ("OK" in out or "ERROR" in out):
                break
        for line in out.replace(chr(13), "").split(chr(10)):
            if line.strip():
                print("<<", line.strip(), flush=True)
        return out

    async def cmd(self, c: str) -> str:
        await self.send(c)
        return await self.read()


def level_digit() -> int:
    try:
        v = max(0, min(100, int(LEVEL_FILE.read_text().strip())))
    except Exception:
        v = 50
    return round(v / 100 * 9)


async def main():
    phone = await find_phone()
    if phone is None:
        raise SystemExit(f"Kein gekoppeltes Geraet mit '{NAME_PART}' im Namen. Erst koppeln.")
    print("iPhone gefunden:", phone.name)

    res = await phone.get_rfcomm_services_for_id_async(RfcommServiceId.from_uuid(HFP_AG))
    services = list(res.services)
    if not services:
        raise SystemExit("Kein Freisprech-Dienst (0x111F) am iPhone gefunden.")
    svc = services[0]

    sock = StreamSocket()
    await sock.connect_async(svc.connection_host_name, svc.connection_service_name)
    print("RFCOMM verbunden")

    at = At(sock)
    await at.cmd("AT+BRSF=0")
    await at.cmd("AT+CIND=?")
    await at.cmd("AT+CIND?")
    await at.cmd("AT+CMER=3,0,0,1")
    await at.cmd("AT+XAPL=0505-0012-0100,2")

    last = None
    while True:
        d = level_digit()
        if d != last:
            await at.cmd(f"AT+IPHONEACCEV=1,1,{d}")
            last = d
            print(f"Akku gemeldet: Stufe {d} von 9", flush=True)
        await at.read(until_ok=False, timeout=2.0)


asyncio.run(main())
