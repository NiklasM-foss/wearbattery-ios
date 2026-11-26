import SwiftUI

@main
struct WearBatteryApp: App {
    @StateObject private var ble = BleMonitor.shared
    @StateObject private var health = HealthSync.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(ble).environmentObject(health)
        }
    }
}
