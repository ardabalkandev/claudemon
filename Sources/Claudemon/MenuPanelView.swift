import SwiftUI
import AppKit
import ClaudemonCore

/// Rich panel shown when the menu-bar item is clicked.
struct MenuPanelView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var notifications: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            content

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Claudemon")
                .font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let report = store.lastGoodReport {
            VStack(spacing: 14) {
                ForEach(report.metrics) { metric in
                    MetricRow(metric: metric)
                }
            }
            // Only a GENUINE failure (while showing last-good data) gets an
            // alarming banner. A stale-render miss (CLI returned no new limit
            // lines this cycle) shows nothing alarming — the data is still valid.
            if store.isStaleError, let error = store.errorMessage {
                stateBanner(text: "Showing last update — \(error)",
                            systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        } else if store.isNotInstalled {
            onboardingNotInstalled
        } else if store.isNotSignedIn {
            onboardingNotSignedIn
        } else if let error = store.errorMessage {
            stateBanner(text: error, systemImage: "xmark.octagon.fill", color: .red)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for usage data…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Onboarding states (calm, not alarming)

    private var onboardingNotInstalled: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude Code isn't installed", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
            Text("Claudemon reads your usage from the Claude Code CLI. Install it, then Claudemon will pick it up automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            installCommand("npm install -g @anthropic-ai/claude-code")
            Link(destination: URL(string: "https://claude.ai/download")!) {
                Label("Get Claude Code", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude Code isn't installed. Install the Claude Code CLI, then Claudemon will pick it up.")
    }

    private var onboardingNotSignedIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sign in to Claude Code", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text("Claude Code is installed but not signed in. Open a terminal, run claude, then use /login.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            installCommand("claude")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign in to Claude Code. Run claude in a terminal, then use slash login.")
    }

    /// A monospaced, copyable command chip.
    private func installCommand(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func stateBanner(text: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Notification settings

    @ViewBuilder
    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $notifications.isEnabled) {
                Label("Usage alerts", systemImage: "bell")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if notifications.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(NotificationManager.Threshold.allCases, id: \.rawValue) { threshold in
                        Toggle(threshold.settingsLabel, isOn: Binding(
                            get: { notifications.isThresholdEnabled(threshold) },
                            set: { notifications.setThreshold(threshold, enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                    }

                    if notifications.permissionDenied {
                        Button {
                            openNotificationSettings()
                        } label: {
                            Label("Enable notifications in System Settings…",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .help("macOS is blocking Claudemon's notifications. Allow them in System Settings > Notifications.")
                    } else {
                        Text("Alerts fire once per quota window for each tracked limit.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $store.floatingEnabled) {
                Label("Floating widget", systemImage: "rectangle.on.rectangle")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $loginItem.isEnabled) {
                Label("Launch at login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            notificationSettings

            if loginItem.requiresApproval {
                Button {
                    loginItem.openLoginItemsSettings()
                } label: {
                    Label("Approve in System Settings…", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .help("Open System Settings > General > Login Items to allow Claudemon to launch at login.")
            }

            HStack {
                if let updated = store.lastUpdated {
                    // lastUpdated reflects the last SUCCESSFUL capture. Calm
                    // wording with a muted "· stale" only once data is >10 min old.
                    Text("Updated \(UsageFormatting.clockString(updated))\(store.dataAge.map { $0 > 10 * 60 ? " · stale" : "" } ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for usage data…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
        }
    }
}

/// A single labeled metric row: name, percent, progress bar, countdown.
struct MetricRow: View {
    let metric: UsageMetric

    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(metric.kind.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(metric.percent)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(UsageColor.color(for: metric.percent))
            }

            ProgressView(value: Double(metric.percent), total: 100)
                .progressViewStyle(.linear)
                .tint(UsageColor.color(for: metric.percent))

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(resetDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.kind.displayName), \(metric.percent) percent used. \(resetDescription)")
        .onReceive(ticker) { now = $0 }
    }

    private var resetDescription: String {
        let countdown = UsageFormatting.countdownString(to: metric.resetDate, now: now)
        let absolute = UsageFormatting.absoluteResetString(date: metric.resetDate, timezone: metric.timezone)
        switch (countdown, absolute) {
        case let (c?, a?): return "resets in \(c) · \(a)"
        case let (c?, nil): return "resets in \(c)"
        case let (nil, a?): return "resets \(a)"
        default: return "reset time unknown"
        }
    }
}
