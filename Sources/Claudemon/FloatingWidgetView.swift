import SwiftUI
import ClaudemonCore

/// Compact always-on-top widget content. Renders one of two forms:
/// - LARGE: a session ring + weekly bars + footer.
/// - MINI:  just the session ring (percent + "SESSION").
/// Double-clicking the panel toggles between them (wired in the controller).
struct FloatingWidgetView: View {

    /// Content sizes for each form, shared with `FloatingPanelController` so it
    /// can resize the hosting panel to match the rendered form.
    static let largeContentSize = CGSize(width: 210, height: 112)
    static let miniContentSize = CGSize(width: 88, height: 88)

    @ObservedObject var store: UsageStore

    private var showOnboarding: Bool {
        !hasData && (store.isNotInstalled || store.isNotSignedIn)
    }

    /// Onboarding has nothing meaningful to show in the mini ring, so it always
    /// falls back to the large form.
    private var isCompact: Bool { store.floatingCompact && !showOnboarding }

    var body: some View {
        Group {
            if isCompact {
                miniBody
            } else {
                largeBody
            }
        }
        // Allow dragging the borderless panel from anywhere on the surface.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Double-click to switch between the mini and full view")
    }

    // MARK: - Large form

    private var largeBody: some View {
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
        .frame(width: Self.largeContentSize.width, height: Self.largeContentSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Mini form

    /// A single, larger session ring centered in a compact rounded-square panel.
    /// Reuses the exact ring rendering/colors of the large form.
    private var miniBody: some View {
        sessionRingView(diameter: 62, lineWidth: 7, percentFont: 18, labelFont: 8)
            .frame(width: Self.miniContentSize.width, height: Self.miniContentSize.height)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
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

    /// The large form's session ring (preserved sizing).
    private var sessionRing: some View {
        sessionRingView(diameter: 58, lineWidth: 7, percentFont: 17, labelFont: 8)
    }

    /// Shared session-ring rendering used by both the large and mini forms.
    /// Same track/trim/color logic; only the dimensions and type scale differ.
    private func sessionRingView(
        diameter: CGFloat,
        lineWidth: CGFloat,
        percentFont: CGFloat,
        labelFont: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(sessionPercent, 100)) / 100.0)
                .stroke(
                    UsageColor.color(for: sessionPercent),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                if hasData {
                    Text("\(sessionPercent)%")
                        .font(.system(size: percentFont, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: store.errorMessage != nil ? "exclamationmark.triangle" : "ellipsis")
                        .font(.system(size: percentFont * 0.82, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text("session")
                    .font(.system(size: labelFont, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
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
