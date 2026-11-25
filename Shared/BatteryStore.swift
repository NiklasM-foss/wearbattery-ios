import Foundation

/// Gemeinsamer Speicher von App und Widget (App Group).
enum BatteryStore {
    static let group = "group.de.wearbattery"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static var level: Int? {
        get { defaults.object(forKey: "level") as? Int }
        set { defaults.set(newValue, forKey: "level") }
    }
    static var updated: Date? {
        get { defaults.object(forKey: "updated") as? Date }
        set { defaults.set(newValue, forKey: "updated") }
    }
    static var peripheralID: String? {
        get { defaults.string(forKey: "peripheralID") }
        set { defaults.set(newValue, forKey: "peripheralID") }
    }
    static var peripheralName: String? {
        get { defaults.string(forKey: "peripheralName") }
        set { defaults.set(newValue, forKey: "peripheralName") }
    }
}
