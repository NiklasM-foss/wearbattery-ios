import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let level: Int?
    let name: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, level: 80, name: "Uhr") }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Die App laedt die Timeline bei jedem neuen Wert neu. Zusaetzlich alle 15 Minuten.
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(900))))
    }

    private func current() -> Entry {
        Entry(date: BatteryStore.updated ?? .now, level: BatteryStore.level,
              name: BatteryStore.peripheralName ?? "Uhr")
    }
}

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    private var text: String { entry.level.map { "\($0)" } ?? "-" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.level ?? 0), in: 0...100) {
                Image(systemName: "applewatch")
            } currentValueLabel: {
                Text(text)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.name).font(.headline)
                Text("\(text) %")
                ProgressView(value: Double(entry.level ?? 0), total: 100)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: "applewatch").font(.title2)
                Text("\(text) %").font(.system(size: 34, weight: .bold, design: .rounded))
                Text(entry.name).font(.caption).foregroundStyle(.secondary)
                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

@main
struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BatteryWidget", provider: Provider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Uhr-Akku")
        .description("Zeigt den Akkustand deiner Uhr.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
