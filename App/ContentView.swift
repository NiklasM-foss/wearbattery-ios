import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BleMonitor

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
                Section("Widget") {
                    Text("Halte auf dem Home-Bildschirm gedrueckt, tippe auf + und waehle Uhr-Akku.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Uhr-Akku")
        }
    }
}
