import SwiftUI
import ClaudemonCore

/// Compact always-on-top widget content: a session ring + weekly bars.
struct FloatingWidgetView: View {
    @ObservedObject var store: UsageStore

    private var showOnboarding: Bool {
        !hasData && (store.isNotInstalled || store.isNotSignedIn)
    }

    var body: some View {
        Group {
            if showOnboarding {
                onboardingContent
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        sessionRing
                        weeklyColumn
                    }
                    footer
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 210, height: 112)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        // Allow dragging the borderless panel from anywhere on the surface.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Onboarding (calm)

    private var onboardingContent: some View {
        VStack(spacing: 8) {
            Image(systemName: store.isNotInstalled ? "shippingbox" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(store.isNotInstalled ? "Claude Code isn't installed" : "Sign in to Claude Code")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(store.isNotInstalled ? "Install the CLI, then Claudemon picks it up." : "Run claude, then /login.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionPercent: Int { store.lastGoodReport?.session?.percent ?? 0 }
    private var weekPercent: Int { store.lastGoodReport?.weekAll?.percent ?? 0 }
    private var sonnetPercent: Int { store.lastGoodReport?.weekSonnet?.percent ?? 0 }

    private var hasData: Bool { store.lastGoodReport != nil }

    // MARK: - Ring

    private var sessionRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(min(sessionPercent, 100)) / 100.0)
                .stroke(
                    UsageColor.color(for: sessionPercent),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                if hasData {
                    Text("\(sessionPercent)%")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: store.errorMessage != nil ? "exclamationmark.triangle" : "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text("session")
                    .font(.system(size: 8, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
    }

    // MARK: - Right column

    private var weeklyColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            metricLine(label: "Week", percent: weekPercent)
            metricLine(label: "Sonnet", percent: sonnetPercent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricLine(label: String, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(hasData ? "\(percent)%" : "—")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(hasData ? UsageColor.color(for: percent) : .secondary)
            }
            UsageBar(percent: hasData ? percent : 0, height: 5)
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        HStack(spacing: 4) {
            if !hasData {
                // No data yet OR genuine error with nothing to show.
                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Waiting for usage data…")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if store.isStaleError {
                // A real failure while showing last-good data — calm orange hint.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text(footerTimeText(prefix: "last update "))
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                // Fresh OR stale-render (no new limit lines this cycle): calm.
                Text(footerTimeText(prefix: "updated "))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerTimeText(prefix: String) -> String {
        guard let updated = store.lastUpdated else { return prefix.trimmingCharacters(in: .whitespaces) }
        let resetSuffix = sessionResetSuffix
        let staleHint = (store.dataAge ?? 0) > 10 * 60 ? " · stale" : ""
        return prefix + UsageFormatting.shortClockString(updated) + resetSuffix + staleHint
    }

    /// " · resets at HH:mm" in the session metric's own timezone, or "" when
    /// no session reset date is available.
    private var sessionResetSuffix: String {
        guard let session = store.lastGoodReport?.session, let resetDate = session.resetDate else { return "" }
        return " · resets at " + UsageFormatting.shortClockString(resetDate, timeZone: session.timezone)
    }

    private var accessibilitySummary: String {
        if store.isNotInstalled { return "Claude Code isn't installed. Install the CLI to see usage." }
        if store.isNotSignedIn { return "Sign in to Claude Code. Run claude then slash login." }
        guard hasData else { return store.errorMessage ?? "Loading usage" }
        var summary = "Session \(sessionPercent) percent, Week \(weekPercent) percent, Sonnet \(sonnetPercent) percent"
        if let session = store.lastGoodReport?.session, let resetDate = session.resetDate {
            summary += ", session resets at \(UsageFormatting.shortClockString(resetDate, timeZone: session.timezone))"
        }
        return summary
    }
}
