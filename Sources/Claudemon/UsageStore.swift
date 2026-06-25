import Foundation
import Combine
import SwiftUI
import WidgetKit
import ClaudemonCore

/// The single source of truth for usage data. Owns the 60s polling timer,
/// performs an immediate refresh on launch, runs the subprocess off the main
/// thread, parses, and publishes state to all observing surfaces.
@MainActor
final class UsageStore: ObservableObject {

    enum State: Equatable {
        case loading                          // first load in progress, no data yet
        case loaded(UsageReport)              // fresh data this tick
        case staleRender(UsageReport)         // last-good kept; CLI returned no new
                                              // limit lines this cycle (NOT an error)
        case staleError(UsageReport, error: String) // last-good kept; real failure
        case error(String)                    // no data and a real error
    }

    /// A classified failure, used to drive distinct, friendly onboarding UI.
    enum Diagnostic: Equatable {
        case notInstalled   // claude binary not found anywhere → onboarding
        case notSignedIn    // claude present but not logged in / no subscription
        case other(String)  // any other genuine error (timeout, launch, etc.)
    }

    @Published private(set) var state: State = .loading
    /// Timestamp of the last SUCCESSFUL capture (the data currently shown).
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing: Bool = false
    /// The current classified diagnostic, if the latest poll genuinely failed.
    /// nil while loading, fresh, or in a calm stale-render.
    @Published private(set) var diagnostic: Diagnostic?

    /// Whether the floating widget is shown. Persisted in UserDefaults.
    @Published var floatingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingEnabled, forKey: Self.floatingDefaultsKey)
            floatingChange?(floatingEnabled)
        }
    }

    /// Callback fired when the floating toggle changes (wired by the app).
    var floatingChange: ((Bool) -> Void)?

    static let floatingDefaultsKey = "floatingWidgetEnabled"
    private let pollInterval: TimeInterval = 60
    private var timer: Timer?
    private var currentTask: Task<Void, Never>?

    // Accelerated follow-up after a stale-render miss. The `claude` CLI refreshes
    // its limit lines on a ~1-minute internal cadence and returns a local-only
    // body in between; tight retries are proven useless and only burn quota. So
    // after a MISS we poll once sooner (~28s) to catch the next refresh window,
    // capped to a couple in a row, then fall back to the normal 60s cadence.
    private let acceleratedInterval: TimeInterval = 28
    private let maxAcceleratedPolls = 2
    private var acceleratedPollsRemaining = 0
    private var followUpWork: DispatchWorkItem?

    // Widget reload rate-limiting. Apple throttles widget reloads (~40-70/day),
    // so we only reload when the data meaningfully changed OR at most every 15
    // minutes. The menu bar / floating panel stay genuinely live regardless.
    private let cache = SharedUsageCache.shared
    private let minReloadInterval: TimeInterval = 15 * 60
    private var lastReloadAt: Date?
    private var lastReloadedSnapshot: [UsageMetric.Kind: Int] = [:]

    init() {
        self.floatingEnabled = UserDefaults.standard.bool(forKey: Self.floatingDefaultsKey)
    }

    // MARK: - Lifecycle

    func start() {
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentTask?.cancel()
        currentTask = nil
        followUpWork?.cancel()
        followUpWork = nil
        acceleratedPollsRemaining = 0
        // Clear the in-flight flag so a later start() is never permanently
        // blocked by a refresh that was cancelled mid-flight.
        isRefreshing = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Tolerance reduces wakeups / battery impact.
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Refresh

    func refresh() {
        // Don't pile up overlapping fetches.
        guard !isRefreshing else { return }
        isRefreshing = true

        // Run the whole fetch + parse off the main actor. resolveClaudePath()
        // and whichClaude() spawn a synchronous login shell, so they must not
        // execute on the main thread (would hang the menu-bar UI on first
        // launch / after wake). Only the result is marshalled back.
        currentTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try await UsageFetcher.fetchUsageJSON()
                let report = try UsageParser.parse(jsonData: data)
                try Task.checkCancellation()
                await self?.applySuccess(report)
            } catch is CancellationError {
                await self?.refreshCancelled()
            } catch let parseError as UsageParseError where parseError.isStaleRender {
                // SUCCESS body that simply lacked the limit lines this cycle.
                // Not a failure: keep last-good data, no alarming error.
                await self?.applyStaleRender()
            } catch {
                await self?.applyFailure(error)
            }
        }
    }

    private func applySuccess(_ report: UsageReport) {
        // A genuine hit: cancel any accelerated follow-up and resume normal pace.
        acceleratedPollsRemaining = 0
        followUpWork?.cancel()
        followUpWork = nil

        state = .loaded(report)
        diagnostic = nil
        lastUpdated = report.capturedAt
        isRefreshing = false

        // Fire usage-limit alerts on genuinely fresh data only (never on
        // stale-render or error states, which reuse last-good data).
        NotificationManager.shared.evaluate(report)

        // Bridge to the widget via the App Group cache, then reload the widget
        // timeline only when something meaningfully changed or the rate-limit
        // window has elapsed.
        cache.writeSuccess(report)
        reloadWidgetIfNeeded(for: report)
    }

    /// The CLI returned a real body but without the three limit lines (it only
    /// refreshes them on its own ~1-minute cadence). Keep last-good data and
    /// show a CALM state — never an error. Schedule a sooner follow-up poll to
    /// catch the next refresh window without hammering the CLI.
    private func applyStaleRender() {
        diagnostic = nil   // calm: not an error
        if let report = lastGoodReport {
            state = .staleRender(report)
            // Keep the cache "ok" with the last-good data; this isn't an error.
            // Preserve the ORIGINAL capture time so the widget's "as of" stays
            // honest (we did not get newer data this tick).
            cache.write(CachedUsage(report: report, state: .ok,
                                    errorMessage: nil, writtenAt: report.capturedAt))
        } else {
            // No data yet (e.g. right after launch before the first hit):
            // stay in a neutral loading/waiting state, NOT an error.
            state = .loading
        }
        isRefreshing = false
        scheduleAcceleratedFollowUpIfNeeded()
    }

    /// Called when an in-flight refresh was cancelled (e.g. by stop()/sleep).
    /// Resets the in-flight flag so future refreshes are not blocked.
    private func refreshCancelled() {
        isRefreshing = false
    }

    private func applyFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostic = Self.classify(error)
        // Preserve last good data as a (real) error-stale, if we have any.
        if let report = lastGoodReport {
            state = .staleError(report, error: message)
            cache.writeStale(report, error: message)
        } else {
            state = .error(message)
            cache.writeError(message)
        }
        isRefreshing = false
        // Do not force a widget reload on transient failures; the widget keeps
        // showing its last-good cache and refreshes on its own timeline policy.
    }

    /// Map a fetch error to a user-facing diagnostic category.
    static func classify(_ error: Error) -> Diagnostic {
        guard let fetchError = error as? UsageFetchError else {
            return .other((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        switch fetchError {
        case .claudeNotFound: return .notInstalled
        case .notSignedIn: return .notSignedIn
        default: return .other(fetchError.errorDescription ?? "Couldn't read usage")
        }
    }

    /// Schedule one sooner follow-up poll after a stale-render miss, capped so we
    /// don't accelerate indefinitely. A genuine hit resets the counter.
    private func scheduleAcceleratedFollowUpIfNeeded() {
        guard timer != nil else { return } // only while actively polling
        if acceleratedPollsRemaining == 0 {
            acceleratedPollsRemaining = maxAcceleratedPolls
        } else {
            acceleratedPollsRemaining -= 1
            guard acceleratedPollsRemaining > 0 else { return }
        }
        followUpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        followUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + acceleratedInterval, execute: work)
    }

    /// Reload the widget timeline only if a percent changed or it has been at
    /// least `minReloadInterval` since the last reload (whichever comes first).
    private func reloadWidgetIfNeeded(for report: UsageReport) {
        let snapshot = Dictionary(uniqueKeysWithValues: report.metrics.map { ($0.kind, $0.percent) })
        let changed = snapshot != lastReloadedSnapshot
        let now = Date()
        let elapsedEnough = lastReloadAt.map { now.timeIntervalSince($0) >= minReloadInterval } ?? true

        guard changed || elapsedEnough else { return }

        WidgetCenter.shared.reloadTimelines(ofKind: claudemonWidgetKind)
        lastReloadAt = now
        lastReloadedSnapshot = snapshot
    }

    // MARK: - Derived accessors

    /// The last successfully parsed report, regardless of current state.
    var lastGoodReport: UsageReport? {
        switch state {
        case .loaded(let r), .staleRender(let r), .staleError(let r, _): return r
        case .loading, .error: return nil
        }
    }

    /// A genuine error message to surface in the error UI. nil for calm states
    /// (loaded / stale-render / loading) — those must NOT look like problems.
    var errorMessage: String? {
        switch state {
        case .error(let m), .staleError(_, let m): return m
        case .loading, .loaded, .staleRender: return nil
        }
    }

    /// True only for a REAL failure while showing last-good data (alarming UI).
    var isStaleError: Bool {
        if case .staleError = state { return true }
        return false
    }

    /// Claude Code isn't installed anywhere we can find → friendly onboarding.
    var isNotInstalled: Bool { diagnostic == .notInstalled }

    /// Claude is present but the user needs to sign in.
    var isNotSignedIn: Bool { diagnostic == .notSignedIn }

    /// True when we have no usable data AND a genuine failure to explain.
    var hasNoData: Bool { lastGoodReport == nil }

    /// How long ago the currently-shown data was captured, if any.
    var dataAge: TimeInterval? {
        lastUpdated.map { Date().timeIntervalSince($0) }
    }

    /// A calm footer string for surfaces that show last-good data.
    /// e.g. "updated 14:32", optionally a muted "· stale" hint when the shown
    /// data is older than ~10 minutes. Never alarming.
    func calmFooterText(now: Date = Date()) -> String? {
        guard let updated = lastUpdated else { return nil }
        var text = "updated \(UsageFormatting.shortClockString(updated))"
        if now.timeIntervalSince(updated) > 10 * 60 {
            text += " · stale"
        }
        return text
    }

    /// Session percent for the compact menu-bar label, if available.
    var sessionPercent: Int? {
        lastGoodReport?.session?.percent
    }
}
