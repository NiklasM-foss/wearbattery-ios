import Foundation
import CoreBluetooth
import HealthKit

/// Holt die gesammelten Gesundheitsdaten von der Uhr ab (Protokoll: siehe docs/health-protokoll.md
/// im Projekt der Watch-App) und schreibt sie in Apple Health.
final class HealthSync: NSObject, ObservableObject {
    static let shared = HealthSync()

    static let service = CBUUID(string: "7F1C0001-9D5E-4C1A-8B3F-2E6A40F1B001")
    static let dataUUID = CBUUID(string: "7F1C0002-9D5E-4C1A-8B3F-2E6A40F1B001")
    static let controlUUID = CBUUID(string: "7F1C0003-9D5E-4C1A-8B3F-2E6A40F1B001")
    static let statusUUID = CBUUID(string: "7F1C0004-9D5E-4C1A-8B3F-2E6A40F1B001")

    struct Record {
        let seq: UInt32
        let kind: UInt8
        let start: Date
        let end: Date
        let value: Double
    }

    @Published var status = "Starte ..."
    @Published var lastSync: Date? = UserDefaults.standard.object(forKey: "health.lastSync") as? Date
    @Published var savedTotal: Int = UserDefaults.standard.integer(forKey: "health.savedTotal")
    @Published var lastBatch: Int = 0
    @Published var connected = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var dataChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    private var buffer: [Record] = []
    private var syncing = false
    private let store = HKHealthStore()

    private var lastSeq: UInt32 {
        get { UInt32(truncatingIfNeeded: UserDefaults.standard.integer(forKey: "health.lastSeq")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "health.lastSeq") }
    }
    private var savedPeripheralID: String? {
        get { UserDefaults.standard.string(forKey: "health.peripheral") }
        set { UserDefaults.standard.set(newValue, forKey: "health.peripheral") }
    }

    private override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "de.wearbattery.health"]
        )
    }

    // MARK: Apple Health

    private var writeTypes: Set<HKSampleType> {
        [HKQuantityType(.heartRate), HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.activeEnergyBurned), HKQuantityType(.flightsClimbed)]
    }

    func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Health ist hier nicht verfuegbar"; return }
        store.requestAuthorization(toShare: writeTypes, read: []) { ok, error in
            DispatchQueue.main.async {
                self.status = ok ? "Health freigegeben" : "Health abgelehnt: \(error?.localizedDescription ?? "")"
            }
        }
    }

    private func samples(from records: [Record]) -> [HKQuantitySample] {
        var out: [HKQuantitySample] = []
        for r in records {
            let type: HKQuantityType
            let unit: HKUnit
            switch r.kind {
            case 1: type = HKQuantityType(.heartRate); unit = HKUnit.count().unitDivided(by: .minute())
            case 2: type = HKQuantityType(.stepCount); unit = .count()
            case 3: type = HKQuantityType(.distanceWalkingRunning); unit = .meter()
            case 4: type = HKQuantityType(.activeEnergyBurned); unit = .kilocalorie()
            case 5: type = HKQuantityType(.flightsClimbed); unit = .count()
            default: continue   // Hoehe und Tageswerte werden nicht geschrieben
            }
            if r.value <= 0 { continue }
            // Zuwachs-Arten brauchen ein echtes Intervall
            if r.kind != 1 && r.end <= r.start { continue }
            let meta: [String: Any] = [
                HKMetadataKeySyncIdentifier: "wearos-\(r.seq)",
                HKMetadataKeySyncVersion: 1,
            ]
            out.append(HKQuantitySample(
                type: type, quantity: HKQuantity(unit: unit, doubleValue: r.value),
                start: r.start, end: r.end, metadata: meta))
        }
        return out
    }

    // MARK: Abholen

    func requestData() {
        guard let p = peripheral, let c = control, !syncing else { return }
        syncing = true
        buffer = []
        status = "Hole Daten ab Nummer \(lastSeq) ..."
        var bytes: [UInt8] = [1]
        withUnsafeBytes(of: lastSeq.littleEndian) { bytes.append(contentsOf: $0) }
        p.writeValue(Data(bytes), for: c, type: .withoutResponse)
    }

    private func acknowledge(_ seq: UInt32) {
        guard let p = peripheral, let c = control else { return }
        var bytes: [UInt8] = [2]
        withUnsafeBytes(of: seq.littleEndian) { bytes.append(contentsOf: $0) }
        p.writeValue(Data(bytes), for: c, type: .withoutResponse)
    }

    private func finish(endSeq: UInt32) {
        let records = buffer
        buffer = []
        guard !records.isEmpty else {
            syncing = false
            DispatchQueue.main.async { self.status = "Verbunden, nichts Neues" }
            return
        }
        let toSave = samples(from: records)
        let finalSeq = max(endSeq, records.map { $0.seq }.max() ?? endSeq)

        let done: (Bool, String?) -> Void = { ok, message in
            DispatchQueue.main.async {
                self.syncing = false
                if ok {
                    self.lastSeq = finalSeq
                    self.acknowledge(finalSeq)
                    self.lastBatch = toSave.count
                    self.savedTotal += toSave.count
                    self.lastSync = Date()
                    UserDefaults.standard.set(self.savedTotal, forKey: "health.savedTotal")
                    UserDefaults.standard.set(self.lastSync, forKey: "health.lastSync")
                    self.status = "\(toSave.count) Werte in Health gespeichert"
                } else {
                    // Nicht quittieren: die Uhr behaelt die Daten, wir holen sie spaeter erneut.
                    self.status = "Speichern fehlgeschlagen: \(message ?? "unbekannt")"
                }
            }
        }

        if toSave.isEmpty { done(true, nil); return }
        store.save(toSave) { ok, error in done(ok, error?.localizedDescription) }
    }

    private func parse(_ d: Data) -> Record? {
        guard d.count >= 17 else { return nil }
        func u32(_ o: Int) -> UInt32 {
            UInt32(d[d.startIndex + o]) | UInt32(d[d.startIndex + o + 1]) << 8
                | UInt32(d[d.startIndex + o + 2]) << 16 | UInt32(d[d.startIndex + o + 3]) << 24
        }
        let value = Float(bitPattern: u32(13))
        return Record(seq: u32(0), kind: d[d.startIndex + 4],
                      start: Date(timeIntervalSince1970: Double(u32(5))),
                      end: Date(timeIntervalSince1970: Double(u32(9))),
                      value: Double(value))
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        status = "Verbinde mit der Uhr ..."
        central.connect(p, options: nil)
    }
}

extension HealthSync: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { status = "Bluetooth nicht verfuegbar"; return }
        if peripheral == nil {
            if let s = savedPeripheralID, let id = UUID(uuidString: s),
               let p = c.retrievePeripherals(withIdentifiers: [id]).first {
                connect(p)
            } else {
                status = "Suche die Uhr ..."
                c.scanForPeripherals(withServices: [Self.service], options: nil)
            }
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            peripheral = p
            p.delegate = self
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        c.stopScan()
        savedPeripheralID = p.identifier.uuidString
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connected = true
        status = "Verbunden"
        p.discoverServices([Self.service])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connected = false
        syncing = false
        status = "Getrennt, warte auf die Uhr ..."
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "Verbindung fehlgeschlagen, neuer Versuch ..."
        connect(p)
    }
}

extension HealthSync: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { return }
        p.discoverCharacteristics([Self.dataUUID, Self.controlUUID, Self.statusUUID], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case Self.dataUUID: dataChar = ch; p.setNotifyValue(true, for: ch)
            case Self.controlUUID: control = ch
            case Self.statusUUID: statusChar = ch; p.setNotifyValue(true, for: ch); p.readValue(for: ch)
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        // Sobald DATA abonniert ist, einmal abholen.
        if ch.uuid == Self.dataUUID, ch.isNotifying { requestData() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        if ch.uuid == Self.dataUUID {
            guard let r = parse(d) else { return }
            if r.kind == 0 { finish(endSeq: r.seq) } else { buffer.append(r) }
        } else if ch.uuid == Self.statusUUID, d.count >= 4 {
            let last = UInt32(d[d.startIndex]) | UInt32(d[d.startIndex + 1]) << 8
                | UInt32(d[d.startIndex + 2]) << 16 | UInt32(d[d.startIndex + 3]) << 24
            if last > lastSeq { requestData() }
        }
    }
}
