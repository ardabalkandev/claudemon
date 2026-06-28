import WidgetKit
import SwiftUI
import ClaudemonCore

/// Widget body: switches layout by family. Reuses ClaudemonCore color/format.
struct ClaudemonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let report = entry.report {
            switch family {
            case .systemSmall:
                SmallUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
            default:
                MediumUsageView(report: report, capturedAt: entry.capturedAt, isStale: entry.isStale)
            }
        } else {
            EmptyUsageView()
        }
    }
}

// MARK: - Small: session ring + weekly percent

struct SmallUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    private var session: Int { report.session?.percent ?? 0 }
    private var week: Int { report.weekAll?.percent ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ring

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("Week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(week)%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: week))
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)

            Spacer(minLength: 0)

            footerLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session \(session) percent, Week \(week) percent")
    }

    /// Session ring that scales to fill the available width using GeometryReader.
    private var ring: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let lineWidth = max(diameter * 0.10, 4)
            let percentFont = diameter * 0.30
            let captionFont = diameter * 0.11

            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(session, 100)) / 100.0)
                    .stroke(UsageColor.color(for: session),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(session)%")
                        .font(.system(size: percentFont, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("session")
                        .font(.system(size: captionFont, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(lineWidth)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private var footerLine: some View {
        if let capturedAt {
            Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                .font(.caption2)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}

// MARK: - Medium: all three metrics as labeled bars

struct MediumUsageView: View {
    let report: UsageReport
    let capturedAt: Date?
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let capturedAt {
                    Text("\(isStale ? "stale · " : "")as of \(UsageFormatting.shortClockString(capturedAt))")
                        .font(.caption2)
                        .foregroundStyle(isStale ? .orange : .secondary)
                }
            }

            ForEach(report.metrics) { metric in
                bar(for: metric)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(for metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric.kind.shortName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(metric.percent)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: metric.percent))
            }
            UsageBar(percent: metric.percent, height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.kind.displayName), \(metric.percent) percent")
    }
}

// MARK: - Empty / no-cache state

struct EmptyUsageView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Open Claudemon")
                .font(.subheadline.weight(.medium))
            Text("to load your usage")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data. Open Claudemon to load your usage.")
    }
}
