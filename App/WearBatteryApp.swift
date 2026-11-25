import SwiftUI

@main
struct WearBatteryApp: App {
    @StateObject private var ble = BleMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(ble)
        }
    }
}
