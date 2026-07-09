import Foundation

/// Pure, side-effect-free policy for deciding when a tracked quota crosses a
/// usage-limit alert point. Kept network- and UI-free so it can be unit tested
/// in isolation; the app layer wraps it to actually post system notifications.
///
/// All thresholds are expressed as the REMAINING quota percentage. A
/// `UsageMetric.percent` is the percentage *used*, so remaining = 100 - used.
public enum UsageAlertThreshold: Int, CaseIterable, Codable, Sendable {
    case quarter = 25   // 25% of the limit left
    case low = 5        // 5% of the limit left
    case depleted = 0   // limit reached / used up
}

public enum UsageAlertPolicy {

    /// Outcome of evaluating one metric against the alert thresholds.
    public struct Decision: Equatable, Sendable {
        /// The single threshold that should fire a notification now, if any.
        /// Only the most severe newly-crossed threshold fires, so a large jump
        /// between polls yields one accurate alert rather than several.
        public let fire: UsageAlertThreshold?
        /// The window signature to persist (carried through unchanged or reset).
        public let signature: String
        /// The updated set of fired threshold raw values for this window.
        public let fired: Set<Int>

        public init(fire: UsageAlertThreshold?, signature: String, fired: Set<Int>) {
            self.fire = fire
            self.signature = signature
            self.fired = fired
        }
    }

    /// Decide which (if any) threshold to fire for a metric.
    ///
    /// - Parameters:
    ///   - percentUsed: the metric's used percentage (0…100).
    ///   - windowSignature: identifies the current quota window (e.g. the reset
    ///     date). When it differs from `priorSignature`, all fired flags re-arm.
    ///   - priorSignature: the signature stored from the previous evaluation, if
    ///     any.
    ///   - firedThresholds: threshold raw values already notified this window.
    ///   - enabledThresholds: thresholds the user currently has switched on.
    /// - Returns: a `Decision` carrying the threshold to fire and updated state.
    public static func decide(
        percentUsed: Int,
        windowSignature: String,
        priorSignature: String?,
        firedThresholds: Set<Int>,
        enabledThresholds: Set<UsageAlertThreshold>
    ) -> Decision {
        // A new quota window re-arms every threshold.
        var fired = (priorSignature == windowSignature) ? firedThresholds : []

        let remaining = max(0, 100 - percentUsed)

        var newlyCrossed: [UsageAlertThreshold] = []
        for threshold in UsageAlertThreshold.allCases where enabledThresholds.contains(threshold) {
            guard remaining <= threshold.rawValue else { continue }
            guard !fired.contains(threshold.rawValue) else { continue }
            fired.insert(threshold.rawValue)
            newlyCrossed.append(threshold)
        }

        let mostSevere = newlyCrossed.min(by: { $0.rawValue < $1.rawValue })
        return Decision(fire: mostSevere, signature: windowSignature, fired: fired)
    }

    /// Derives the de-dup window signature from a metric's reset date.
    ///
    /// The signature is the ONLY thing that re-arms fired thresholds: when it
    /// changes, `decide` clears the fired set and every enabled threshold can
    /// notify again. So any churn in the signature floods the user with
    /// duplicate banners (observed in the wild). A raw
    /// `timeIntervalSince1970` is far too brittle for that job — it flips on
    /// two independent, common inputs. This helper hardens it with two rules:
    ///
    ///   1. **Bucket to the hour.** The CLI's reported reset time can jitter by
    ///      a minute across polls (e.g. "9:59am" ↔ "10am"); rounding to the
    ///      nearest hour absorbs that while still distinguishing the distinct
    ///      5-hour session windows (which sit whole hours apart) and the
    ///      week-apart weekly windows.
    ///   2. **Inherit on a transient parse-miss.** When `resetDate` is nil
    ///      (a single poll that failed to parse the reset clause) we keep the
    ///      prior signature instead of minting a fresh "unknown" window, so one
    ///      unparseable poll can't re-arm — and re-fire — every threshold.
    ///
    /// A genuinely new quota window still moves the reset by hours/days, so it
    /// produces a new bucket and correctly re-arms exactly once.
    public static func windowSignature(resetDate: Date?, prior: String?) -> String {
        guard let resetDate else { return prior ?? "none" }
        let hourBucket = Int((resetDate.timeIntervalSince1970 / 3600).rounded())
        return "h\(hourBucket)"
    }

    // MARK: - Reset alerts

    /// Per-metric state for the "limit reset" alert. Tracked in memory per app
    /// run (never persisted): a reset is only announced when the app itself
    /// witnesses the window roll over while running, so a reset that happened
    /// while the app was closed doesn't fire a stale banner on next launch.
    public struct ResetWindowState: Equatable, Sendable {
        /// The future reset date observed for the currently-active window, if we
        /// have seen one this run. Nil until the first future reset is observed
        /// (so the first poll after launch never counts as a reset).
        public var pendingResetDate: Date?
        /// Whether the metric was seen with any usage (percent > 0) during the
        /// current window. The reset alert only fires if the window that just
        /// rolled over had actually been used at all — a completely untouched
        /// window (0% used) resets silently.
        public var didUse: Bool

        public init(pendingResetDate: Date? = nil, didUse: Bool = false) {
            self.pendingResetDate = pendingResetDate
            self.didUse = didUse
        }
    }

    /// Outcome of evaluating one metric for the "limit reset" alert.
    public struct ResetDecision: Equatable, Sendable {
        /// True when a reset banner should be posted now.
        public let fireReset: Bool
        /// The updated state to persist back for the next evaluation.
        public let state: ResetWindowState

        public init(fireReset: Bool, state: ResetWindowState) {
            self.fireReset = fireReset
            self.state = state
        }
    }

    /// Decide whether a metric's quota window has just reset (and, if so, whether
    /// to announce it), advancing the per-metric reset state.
    ///
    /// The rule, applied in order each poll:
    ///   1. **Detect a witnessed reset.** If we recorded a future reset date and
    ///      `now` has passed it, the window rolled over. Fire iff the window that
    ///      ended had any usage (`didUse`). Then clear the pending date and usage
    ///      flag so the fresh window starts clean.
    ///   2. **Track the active window.** If the metric reports a future reset
    ///      date, record it as the pending window (this is also what arms the
    ///      very first window after launch — arming, not firing).
    ///   3. **Track usage.** If the metric has any usage (`percentUsed > 0`),
    ///      remember it so the *next* reset of this window announces.
    ///
    /// - Parameters:
    ///   - now: the current time (use the report's capture time).
    ///   - resetDate: the metric's reported reset date, if any.
    ///   - percentUsed: the metric's used percentage (0…100).
    ///   - prior: the state from the previous evaluation (default for first run).
    public static func decideReset(
        now: Date,
        resetDate: Date?,
        percentUsed: Int,
        prior: ResetWindowState
    ) -> ResetDecision {
        var state = prior
        var fireReset = false

        // 1. Witnessed reset: a previously-observed future reset has now passed.
        if let pending = state.pendingResetDate, now >= pending {
            if state.didUse {
                fireReset = true
            }
            state.didUse = false
            state.pendingResetDate = nil
        }

        // 2. Arm/refresh the active window from the latest future reset date.
        if let resetDate, resetDate > now {
            state.pendingResetDate = resetDate
        }

        // 3. Remember any usage within the current window.
        if percentUsed > 0 {
            state.didUse = true
        }

        return ResetDecision(fireReset: fireReset, state: state)
    }
}
