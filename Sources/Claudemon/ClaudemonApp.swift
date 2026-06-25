import SwiftUI
import AppKit
import UserNotifications

@main
struct ClaudemonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The single source of truth, owned by the app and shared with the delegate.
    @StateObject private var store = ClaudemonAppState.shared.store
    @StateObject private var loginItem = ClaudemonAppState.shared.loginItem
    @StateObject private var notifications = ClaudemonAppState.shared.notifications

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(store: store, loginItem: loginItem, notifications: notifications)
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
    private init() {}
}

/// Compact menu-bar label: gauge SF Symbol + live session percent.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: gaugeSymbol)
            if let percent = store.sessionPercent {
                Text("\(percent)%")
            } else if store.isNotInstalled || store.isNotSignedIn {
                // Calm onboarding hint, not a scary error — a neutral dash.
                Text("—")
            } else if store.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .accessibilityLabel(accessibilityLabel)
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
    private var floatingController: FloatingPanelController?

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

        // Restore the floating widget if it was enabled last session.
        if store.floatingEnabled {
            controller.setVisible(true)
        }

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

    // Show banners + play sound even when Claudemon is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    @objc private func systemWillSleep() {
        store.stop()
    }

    @objc private func systemDidWake() {
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
