import Foundation
import CoreBluetooth
import WidgetKit

/// Verbindet sich dauerhaft mit der Uhr und liest den Standard-Akkudienst (0x180F / 0x2A19).
final class BleMonitor: NSObject, ObservableObject {
    static let shared = BleMonitor()

    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    struct Found: Identifiable {
        let id: UUID
        let name: String
        let peripheral: CBPeripheral
    }

    @Published var status = "Starte ..."
    @Published var level: Int? = BatteryStore.level
    @Published var updated: Date? = BatteryStore.updated
    @Published var found: [Found] = []
    @Published var deviceName: String? = BatteryStore.peripheralName

    private var central: CBCentralManager!
    private var watch: CBPeripheral?

    private override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "de.wearbattery.central"]
        )
    }

    func startScan() {
        found = []
        guard central.state == .poweredOn else { status = "Bluetooth ist aus"; return }
        status = "Suche Geraete mit Akku-Dienst ..."
        central.scanForPeripherals(withServices: [Self.batteryService], options: nil)
    }

    func choose(_ f: Found) {
        central.stopScan()
        BatteryStore.peripheralID = f.id.uuidString
        BatteryStore.peripheralName = f.name
        deviceName = f.name
        connect(f.peripheral)
    }

    func forget() {
        if let w = watch { central.cancelPeripheralConnection(w) }
        watch = nil
        BatteryStore.peripheralID = nil
        BatteryStore.peripheralName = nil
        BatteryStore.level = nil
        deviceName = nil
        level = nil
        status = "Kein Geraet gewaehlt"
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func connect(_ p: CBPeripheral) {
        watch = p
        p.delegate = self
        status = "Verbinde mit \(p.name ?? "Uhr") ..."
        // Ohne Zeitlimit: iOS verbindet, sobald die Uhr in Reichweite ist (auch im Hintergrund).
        central.connect(p, options: nil)
    }

    private func reconnectSaved() {
        guard let s = BatteryStore.peripheralID, let id = UUID(uuidString: s) else {
            status = "Kein Geraet gewaehlt. Tippe auf Suchen."
            return
        }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first { connect(p) }
    }

    private func store(_ value: Int) {
        BatteryStore.level = value
        BatteryStore.updated = Date()
        DispatchQueue.main.async {
            self.level = value
            self.updated = BatteryStore.updated
            self.status = "Verbunden"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension BleMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            if watch == nil { reconnectSaved() }
        } else {
            status = "Bluetooth nicht verfuegbar"
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            watch = p
            p.delegate = self
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "Unbekannt"
        if !found.contains(where: { $0.id == p.identifier }) {
            found.append(Found(id: p.identifier, name: name, peripheral: p))
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Verbunden, lese Akku ..."
        p.discoverServices([Self.batteryService])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        status = "Getrennt, warte auf die Uhr ..."
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "Verbindung fehlgeschlagen, neuer Versuch ..."
        connect(p)
    }
}

extension BleMonitor: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        p.discoverCharacteristics([Self.batteryLevel], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
        p.setNotifyValue(true, for: ch)
        p.readValue(for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.batteryLevel, let b = ch.value?.first else { return }
        store(Int(b))
    }
}
