import WidgetKit
import SwiftUI
import ClaudemonCore

// MARK: - Timeline entry

struct UsageEntry: TimelineEntry {
    let date: Date
    /// The cached report, or nil when no cache is available yet.
    let report: UsageReport?
    /// When the cached data was captured (for the "as of" line).
    let capturedAt: Date?
    let isStale: Bool
    /// Exact straight-edged bar fills (app setting, shared via the App Group
    /// defaults suite).
    let preciseBars: Bool
}

// MARK: - Provider (network-free: reads ONLY the App Group cache)

struct UsageProvider: TimelineProvider {

    private let cache = SharedUsageCache.shared

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), report: Self.sampleReport, capturedAt: Date(),
                   isStale: false, preciseBars: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = makeEntry()
        // Best-effort glance view: ask the system to refresh in ~15 minutes.
        // The app also pushes reloads when values change.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Build an entry from the shared cache, falling back gracefully.
    private func makeEntry() -> UsageEntry {
        let precise = PreciseBarsPreference.read()
        guard let cached = cache.read() else {
            return UsageEntry(date: Date(), report: nil, capturedAt: nil,
                              isStale: false, preciseBars: precise)
        }
        return UsageEntry(
            date: Date(),
            report: cached.report,
            capturedAt: cached.report != nil ? cached.writtenAt : nil,
            isStale: cached.state != .ok,
            preciseBars: precise
        )
    }

    /// Sample data for placeholder/preview.
    static var sampleReport: UsageReport {
        UsageReport(metrics: [
            UsageMetric(kind: .session, rawLabel: "Session", percent: 27, resetDate: nil, timezoneIdentifier: nil),
            UsageMetric(kind: .weekAll, rawLabel: "Week", percent: 29, resetDate: nil, timezoneIdentifier: nil),
            UsageMetric(kind: .weekModel, rawLabel: "Current week (Fable)", percent: 2, resetDate: nil, timezoneIdentifier: nil)
        ], capturedAt: Date())
    }
}

// MARK: - Widget definition

struct ClaudemonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: claudemonWidgetKind, provider: UsageProvider()) { entry in
            ClaudemonWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your Claude Code usage limits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ClaudemonWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudemonWidget()
    }
}
