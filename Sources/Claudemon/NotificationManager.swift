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

    /// Master on/off switch for all usage alerts.
    @Published var isEnabled: Bool {
        didSet {
            guard didLoad else { return }
            defaults.set(isEnabled, forKey: Self.masterDefaultsKey)
            if isEnabled { requestAuthorizationIfNeeded() }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.masterDefaultsKey)

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
            let signature = Self.signature(for: metric)
            let prior = firedState[key]

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
        }

        persistFiredState()
    }

    /// A stable identifier for the current quota window. The reset date is the
    /// most reliable signal; when it advances we know a new window began.
    private static func signature(for metric: UsageMetric) -> String {
        if let date = metric.resetDate {
            return String(Int(date.timeIntervalSince1970))
        }
        return "none"
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
        content.subtitle = metric.kind.displayName
        content.body = threshold.bodyText
        content.sound = .default

        // Unique id per fire so banners stack rather than coalesce.
        let id = "claudemon.\(metric.kind.rawValue).\(threshold.rawValue).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Authorization

    /// Ask for permission if the user hasn't decided yet; harmless if already
    /// granted. Updates `permissionDenied` for the UI.
    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self?.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in self?.permissionDenied = !granted }
                }
            case .denied:
                Task { @MainActor in self?.permissionDenied = true }
            default:
                Task { @MainActor in self?.permissionDenied = false }
            }
        }
    }

    /// Refresh `permissionDenied` from the current OS state without prompting.
    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.permissionDenied = settings.authorizationStatus == .denied
            }
        }
    }
}
