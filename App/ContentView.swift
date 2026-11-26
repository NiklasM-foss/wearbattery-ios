import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BleMonitor
    @EnvironmentObject var health: HealthSync

    var body: some View {
        NavigationStack {
            List {
                Section("Uhr") {
                    HStack {
                        Text(ble.deviceName ?? "Keine Uhr gewaehlt")
                        Spacer()
                        Text(ble.level.map { "\($0) %" } ?? "-").font(.title2).bold()
                    }
                    if let u = ble.updated {
                        Text("Stand: \(u.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(ble.status).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Suchen") { ble.startScan() }
                    if ble.deviceName != nil {
                        Button("Vergessen", role: .destructive) { ble.forget() }
                    }
                }
                if !ble.found.isEmpty {
                    Section("Gefunden") {
                        ForEach(ble.found) { f in
                            Button(f.name) { ble.choose(f) }
                        }
                    }
                }
                Section("Gesundheit") {
                    HStack {
                        Text("Verbindung")
                        Spacer()
                        Text(health.connected ? "verbunden" : "getrennt").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("In Health gespeichert")
                        Spacer()
                        Text("\(health.savedTotal)").foregroundStyle(.secondary)
                    }
                    if let u = health.lastSync {
                        Text("Letzter Abgleich: \(u.formatted(date: .abbreviated, time: .shortened)), \(health.lastBatch) Werte")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(health.status).font(.footnote).foregroundStyle(.secondary)
                    Button("Health erlauben") { health.requestHealthAccess() }
                    Button("Jetzt abholen") { health.requestData() }
                }
                Section("Widget") {
                    Text("Halte auf dem Home-Bildschirm gedrueckt, tippe auf + und waehle Uhr-Akku.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Uhr-Akku")
        }
    }
}
