import Foundation
import UserNotifications
import ClaudemonCore

/// UI strings for the shared, testable alert thresholds defined in the core.
extension UsageAlertThreshold {
    /// Label for the per-threshold toggle in the menu.
    var settingsLabel: String {
        switch self {
        case .quarter:  return "At 25% remaining"
        case .low:      return "At 5% remaining"
        case .depleted: return "When depleted"
        }
    }

    /// Notification body. The metric name lives in the subtitle, so the body
    /// stays short and scannable.
    var bodyText: String {
        switch self {
        case .quarter:  return "25% of your limit remaining."
        case .low:      return "Only 5% of your limit left."
        case .depleted: return "Limit reached — your quota is used up."
        }
    }

    var defaultsKey: String { "notify.threshold.\(rawValue)" }
}

/// Notification body for the "limit reset" alert. The metric name lives in the
/// subtitle, so the body stays short and scannable.
private let resetAlertBodyText = "Limit reset — your quota is available again."

/// Owns the local-notification policy: decides when a tracked quota crosses a
/// "remaining %" alert point and posts a single, de-duplicated banner.
///
/// The crossing/de-duplication decision is delegated to the pure, unit-tested
/// `UsageAlertPolicy` in the core; this type only handles persistence, OS
/// authorization, and actually posting the notification.
@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()

    typealias Threshold = UsageAlertThreshold

    // MARK: - Persisted settings

    static let masterDefaultsKey = "notify.enabled"
    static let firedStateDefaultsKey = "notify.firedState.v1"
    static let resetDefaultsKey = "notify.reset.enabled"

    /// Master on/off switch for all usage alerts.
    @Published var isEnabled: Bool {
        didSet {
            guard didLoad else { return }
            defaults.set(isEnabled, forKey: Self.masterDefaultsKey)
            if isEnabled { requestAuthorizationIfNeeded() }
        }
    }

    /// Whether to announce when a tracked limit resets (only for windows that
    /// had any usage). Defaults to on.
    @Published var resetAlertsEnabled: Bool {
        didSet {
            guard didLoad else { return }
            defaults.set(resetAlertsEnabled, forKey: Self.resetDefaultsKey)
        }
    }

    /// Per-threshold enablement. Defaults to on for every threshold.
    @Published private var thresholdEnabled: [Int: Bool]

    /// True when the OS has explicitly denied notification permission, so the
    /// menu can nudge the user toward System Settings.
    @Published private(set) var permissionDenied: Bool = false

    // MARK: - Internals

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var didLoad = false

    /// Per-metric record of which thresholds have already fired in the current
    /// quota window (keyed by `UsageMetric.Kind.rawValue`).
    private struct FiredEntry: Codable {
        var signature: String      // identifies the quota window (reset date)
        var fired: Set<Int>        // threshold rawValues already notified
    }
    private var firedState: [String: FiredEntry]

    /// Per-metric reset-alert state (keyed by `UsageMetric.Kind.rawValue`).
    /// Intentionally in-memory only: it resets on launch so a reset that
    /// happened while the app was closed can't fire a stale banner. See
    /// `UsageAlertPolicy.ResetWindowState`.
    private var resetState: [String: UsageAlertPolicy.ResetWindowState] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.masterDefaultsKey)
        // Absent key → default ON, so resets announce out of the box.
        self.resetAlertsEnabled = defaults.object(forKey: Self.resetDefaultsKey) as? Bool ?? true

        var loaded: [Int: Bool] = [:]
        for threshold in Threshold.allCases {
            // Absent key → default ON, so a fresh enable alerts on all points.
            loaded[threshold.rawValue] = defaults.object(forKey: threshold.defaultsKey) as? Bool ?? true
        }
        self.thresholdEnabled = loaded

        if let data = defaults.data(forKey: Self.firedStateDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: FiredEntry].self, from: data) {
            self.firedState = decoded
        } else {
            self.firedState = [:]
        }

        didLoad = true
        if isEnabled { refreshAuthorizationStatus() }
    }

    // MARK: - Per-threshold access (for SwiftUI bindings)

    func isThresholdEnabled(_ threshold: Threshold) -> Bool {
        thresholdEnabled[threshold.rawValue] ?? true
    }

    func setThreshold(_ threshold: Threshold, enabled: Bool) {
        thresholdEnabled[threshold.rawValue] = enabled
        defaults.set(enabled, forKey: threshold.defaultsKey)
    }

    private var enabledThresholds: Set<Threshold> {
        Set(Threshold.allCases.filter { isThresholdEnabled($0) })
    }

    // MARK: - Evaluation

    /// Inspect a fresh report and fire alerts for any newly-crossed thresholds.
    /// Call this only with genuinely fresh data (never on stale/error states).
    func evaluate(_ report: UsageReport) {
        guard isEnabled else { return }
        let enabled = enabledThresholds

        for metric in report.metrics {
            let key = metric.kind.rawValue
            let prior = firedState[key]
            // Robust, jitter- and parse-miss-tolerant window id. A brittle
            // signature here re-arms every threshold each poll and floods the
            // user with duplicate banners; see UsageAlertPolicy.windowSignature.
            let signature = UsageAlertPolicy.windowSignature(
                resetDate: metric.resetDate, prior: prior?.signature)

            let decision = UsageAlertPolicy.decide(
                percentUsed: metric.percent,
                windowSignature: signature,
                priorSignature: prior?.signature,
                firedThresholds: prior?.fired ?? [],
                enabledThresholds: enabled
            )

            if let threshold = decision.fire {
                post(threshold: threshold, metric: metric)
            }
            firedState[key] = FiredEntry(signature: decision.signature, fired: decision.fired)

            // Reset alerts: track every poll (so depletion is remembered even
            // while the toggle is off), but only post when it's enabled.
            let resetDecision = UsageAlertPolicy.decideReset(
                now: report.capturedAt,
                resetDate: metric.resetDate,
                percentUsed: metric.percent,
                prior: resetState[key] ?? .init()
            )
            resetState[key] = resetDecision.state
            if resetAlertsEnabled, resetDecision.fireReset {
                postReset(metric: metric)
            }
        }

        persistFiredState()
    }

    private func persistFiredState() {
        if let data = try? JSONEncoder().encode(firedState) {
            defaults.set(data, forKey: Self.firedStateDefaultsKey)
        }
    }

    // MARK: - Posting

    private func post(threshold: Threshold, metric: UsageMetric) {
        let content = UNMutableNotificationContent()
        content.title = "Claudemon"
        content.subtitle = metric.displayLabel
        content.body = threshold.bodyText
        content.sound = .default

        // Unique id per fire so banners stack rather than coalesce.
        let id = "claudemon.\(metric.kind.rawValue).\(threshold.rawValue).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    private func postReset(metric: UsageMetric) {
        let content = UNMutableNotificationContent()
        content.title = "Claudemon"
        content.subtitle = metric.displayLabel
        content.body = resetAlertBodyText
        content.sound = .default

        // Unique id per fire so banners stack rather than coalesce.
        let id = "claudemon.reset.\(metric.kind.rawValue).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Authorization

    /// Ask for permission if the user hasn't decided yet; harmless if already
    /// granted. Updates `permissionDenied` for the UI.
    /// Async UNUserNotificationCenter API (not completion handlers) so the
    /// Task inherits this class's main-actor isolation end to end.
    func requestAuthorizationIfNeeded() {
        Task {
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound])
                    permissionDenied = !granted
                } catch {
                    // Rare OS-level failure: surface the "enable in System
                    // Settings" hint rather than silently staying enabled-looking.
                    permissionDenied = true
                }
            case .denied:
                permissionDenied = true
            default:
                permissionDenied = false
            }
        }
    }

    /// Refresh `permissionDenied` from the current OS state without prompting.
    func refreshAuthorizationStatus() {
        Task {
            permissionDenied = await center.notificationSettings().authorizationStatus == .denied
        }
    }
}
