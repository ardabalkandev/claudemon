import Foundation

/// A single usage metric parsed from the `/usage` output.
public struct UsageMetric: Identifiable, Equatable, Codable, Sendable {
    /// Stable identity derived from the kind so SwiftUI diffing is stable.
    public var id: Kind { kind }

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case session
        case weekAll
        case weekSonnet

        public var displayName: String {
            switch self {
            case .session: return "Current Session (5h)"
            case .weekAll: return "Current Week (all models)"
            case .weekSonnet: return "Current Week (Sonnet only)"
            }
        }

        public var shortName: String {
            switch self {
            case .session: return "Session"
            case .weekAll: return "Week"
            case .weekSonnet: return "Sonnet"
            }
        }
    }

    public let kind: Kind
    /// Raw label as it appeared in the source text (best-effort).
    public let rawLabel: String
    /// Percent used, 0...100 (clamped).
    public let percent: Int
    /// Absolute reset date in the metric's timezone, if it could be computed.
    public let resetDate: Date?
    /// IANA timezone identifier (e.g. "Europe/Istanbul"), if parsed.
    public let timezoneIdentifier: String?

    public init(kind: Kind, rawLabel: String, percent: Int, resetDate: Date?, timezoneIdentifier: String?) {
        self.kind = kind
        self.rawLabel = rawLabel
        self.percent = percent
        self.resetDate = resetDate
        self.timezoneIdentifier = timezoneIdentifier
    }

    public var timezone: TimeZone? {
        guard let timezoneIdentifier else { return nil }
        return TimeZone(identifier: timezoneIdentifier)
    }
}

/// A complete usage report containing the three known metrics.
public struct UsageReport: Equatable, Codable, Sendable {
    public let metrics: [UsageMetric]
    /// When this report was produced (local device time).
    public let capturedAt: Date

    public init(metrics: [UsageMetric], capturedAt: Date) {
        self.metrics = metrics
        self.capturedAt = capturedAt
    }

    public func metric(_ kind: UsageMetric.Kind) -> UsageMetric? {
        metrics.first { $0.kind == kind }
    }

    public var session: UsageMetric? { metric(.session) }
    public var weekAll: UsageMetric? { metric(.weekAll) }
    public var weekSonnet: UsageMetric? { metric(.weekSonnet) }
}

// MARK: - Formatting helpers

public enum UsageFormatting {
    /// Returns a compact "Xh Ym" (or "Ym" / "now") countdown string from now
    /// until the supplied reset date. Returns nil if no date.
    public static func countdownString(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }

        let totalMinutes = Int(interval / 60.0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Absolute reset time formatted in the metric's own timezone, e.g.
    /// "Jun 24, 2:49 AM".
    public static func absoluteResetString(date: Date?, timezone: TimeZone?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timezone ?? TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "HH:mm:ss" wall-clock string (local timezone) used for "last updated".
    public static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// "HH:mm" wall-clock string (local timezone) used for the widget's
    /// "as of" line.
    public static func shortClockString(_ date: Date) -> String {
        shortClockString(date, timeZone: nil)
    }

    /// "HH:mm" wall-clock string in the supplied timezone (falls back to the
    /// current timezone when nil). Used for the widget's "resets at" suffix so
    /// the time matches the panel's reset basis (the metric's own timezone).
    public static func shortClockString(_ date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
