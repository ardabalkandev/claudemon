import SwiftUI
import AppKit
import UserNotifications
import ClaudemonCore

@main
struct ClaudemonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The single source of truth, owned by the app and shared with the delegate.
    @StateObject private var store = ClaudemonAppState.shared.store
    @StateObject private var loginItem = ClaudemonAppState.shared.loginItem
    @StateObject private var notifications = ClaudemonAppState.shared.notifications
    @StateObject private var updateChecker = ClaudemonAppState.shared.updateChecker

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(store: store, loginItem: loginItem,
                          notifications: notifications, updateChecker: updateChecker)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Holds app-wide singletons so the AppDelegate and the SwiftUI scene share the
/// exact same instances.
@MainActor
final class ClaudemonAppState {
    static let shared = ClaudemonAppState()
    let store = UsageStore()
    let loginItem = LoginItemManager()
    let notifications = NotificationManager.shared
    let updateChecker = UpdateChecker()
    private init() {}
}

/// Compact menu-bar label: gauge SF Symbol + live session percent, or a
/// rasterized bar graph in the `.bars` display mode.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    // The menu bar renders live label views as template (monochrome) content,
    // so the bar-graph mode is rasterized into a non-template NSImage. These
    // drive the raster's appearance and sharpness.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// Normal (percent present) rendering routes through the user's chosen
    /// display mode. The zero-content states (onboarding / error) override the
    /// mode entirely so the item is never empty and stays clickable.
    @ViewBuilder
    private var content: some View {
        if let percent = store.sessionPercent {
            modeContent(percent: percent)
        } else if store.isNotInstalled || store.isNotSignedIn {
            // Calm onboarding hint, not a scary error — a neutral dash.
            percentText("—")
        } else if store.errorMessage != nil {
            Image(systemName: "exclamationmark.triangle")
        } else {
            // Loading with no data yet: keep a neutral, clickable placeholder.
            percentText("—")
        }
    }

    @ViewBuilder
    private func modeContent(percent: Int) -> some View {
        switch store.menuBarDisplayMode {
        case .iconAndText:
            Image(systemName: gaugeSymbol)
            percentText("\(percent)%")
        case .textOnly:
            percentText("\(percent)%")
        case .iconOnly:
            Image(systemName: gaugeSymbol)
        case .bars:
            if let image = barsImage(sessionPercent: percent) {
                Image(nsImage: image)
            } else {
                // Rasterization failed (shouldn't happen): fall back to text
                // so the item is never empty.
                percentText("\(percent)%")
            }
        }
    }

    /// Rasterize the bar graph into a non-template NSImage so the bars keep
    /// their green/yellow/red colors — the menu bar strips colors from live
    /// SwiftUI label views. Re-evaluated whenever the store publishes or the
    /// menu-bar appearance/scale changes; the view is tiny, so rendering is
    /// cheap at the 60s poll cadence.
    private func barsImage(sessionPercent: Int) -> NSImage? {
        let config = MenuBarBarsView.Configuration(
            sessionPercent: sessionPercent,
            weekPercent: store.menuBarShowsWeekBar ? store.menuBarWeekMetric?.percent : nil,
            showsPercent: store.menuBarShowsPercent,
            isVertical: store.menuBarBarsVertical,
            preciseFill: store.preciseBars,
            halfWidthBars: store.menuBarBarsHalfWidth
        )
        let renderer = ImageRenderer(content: MenuBarBarsView(config)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale > 0
            ? displayScale
            : (NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    /// Percent text at the default menu-bar size with monospaced digits so the
    /// bar item width doesn't jitter as the value changes.
    private func percentText(_ string: String) -> some View {
        Text(string)
            .monospacedDigit()
    }

    /// Pick a gauge glyph roughly reflecting the session fill level. When Claude
    /// Code isn't installed / signed in, show a neutral empty gauge (no alarm).
    private var gaugeSymbol: String {
        guard let p = store.sessionPercent else { return "gauge.with.dots.needle.0percent" }
        switch p {
        case ..<34: return "gauge.with.dots.needle.0percent"
        case 34..<67: return "gauge.with.dots.needle.50percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    private var accessibilityLabel: String {
        if let p = store.sessionPercent {
            if store.menuBarDisplayMode == .bars, store.menuBarShowsWeekBar,
               let week = store.menuBarWeekMetric {
                let name = week.kind == .weekModel ? "\(week.modelName) week" : "week"
                return "Claudemon, session \(p) percent, \(name) \(week.percent) percent used"
            }
            return "Claudemon, session \(p) percent used"
        }
        if store.isNotInstalled { return "Claudemon, Claude Code isn't installed" }
        if store.isNotSignedIn { return "Claudemon, sign in to Claude Code" }
        return store.errorMessage ?? "Claudemon, loading usage"
    }
}

/// AppDelegate handles activation policy (no Dock icon) and the floating panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let store = ClaudemonAppState.shared.store
    private let loginItem = ClaudemonAppState.shared.loginItem
    private let notifications = ClaudemonAppState.shared.notifications
    private let updateChecker = ClaudemonAppState.shared.updateChecker
    private var floatingController: FloatingPanelController?
    private var statusItemClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menu-bar agent: no Dock icon, no app menu.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Present alert banners even while this accessory app is "active", and
        // re-sync the permission state in case it changed in System Settings.
        UNUserNotificationCenter.current().delegate = self
        notifications.refreshAuthorizationStatus()

        let controller = FloatingPanelController(store: store)
        floatingController = controller

        // Wire the store's floating toggle to the panel controller.
        store.floatingChange = { [weak controller] enabled in
            controller?.setVisible(enabled)
        }

        // Begin polling (immediate refresh + 60s timer).
        store.start()

        // Non-blocking, notify-only update check, throttled to once/day.
        maybeCheckForUpdates()

        // Restore the floating widget if it was enabled last session.
        if store.floatingEnabled {
            controller.setVisible(true)
        }

        installStatusItemContextMenu()

        // Pause/resume polling around system sleep to save resources.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake),
                           name: NSWorkspace.didWakeNotification, object: nil)

        // Re-check the login-item status when the app activates, so an approval
        // performed in System Settings is reflected in the toggle.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        loginItem.refreshStatus()
        notifications.refreshAuthorizationStatus()
    }

    /// Fire at most one automatic update check per day. Kept off the launch
    /// path with a detached Task so it never delays the menu-bar appearing.
    private func maybeCheckForUpdates() {
        let key = "lastUpdateCheck"
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           now.timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        // Capture the checker (not self) to avoid a retain cycle. Stamp the
        // once-per-day throttle only AFTER a check that didn't fail, so a
        // transient network failure on launch doesn't burn the day — the next
        // launch will naturally retry.
        Task { [updateChecker] in
            await updateChecker.check()
            if case .failed = updateChecker.state { return }
            UserDefaults.standard.set(now, forKey: key)
        }
    }

    // Show banners + play sound even when Claudemon is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Status item context menu

    /// `MenuBarExtra` has no right-click support, so intercept right-clicks
    /// (and control-clicks) on the status item's window and pop up a small
    /// Refresh / Quit menu instead of the panel. Works for every display mode
    /// since the check is on the window, not the label content.
    private func installStatusItemContextMenu() {
        statusItemClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self,
                  let window = event.window,
                  window.className == "NSStatusBarWindow",
                  let view = window.contentView,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            else { return event }
            self.contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
            return nil // swallow so the panel doesn't toggle underneath
        }
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu),
                                 keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !store.isRefreshing
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Claudemon", action: #selector(quitFromMenu),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func refreshFromMenu() {
        store.refresh()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func systemWillSleep() {
        store.stop()
    }

    @objc private func systemDidWake() {
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let statusItemClickMonitor {
            NSEvent.removeMonitor(statusItemClickMonitor)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
