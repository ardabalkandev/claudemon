import XCTest
@testable import ClaudemonCore

final class UsageAlertPolicyTests: XCTestCase {

    private let allEnabled = Set(UsageAlertThreshold.allCases)

    // MARK: - Crossing

    func testNoAlertWhenPlentyRemaining() {
        // 50% used → 50% remaining: above the 25% point, nothing fires.
        let d = UsageAlertPolicy.decide(
            percentUsed: 50, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: allEnabled)
        XCTAssertNil(d.fire)
        XCTAssertTrue(d.fired.isEmpty)
    }

    func testFiresQuarterAtExactlyTwentyFivePercentRemaining() {
        // 75% used → exactly 25% remaining: the quarter alert fires.
        let d = UsageAlertPolicy.decide(
            percentUsed: 75, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .quarter)
        XCTAssertEqual(d.fired, [25])
    }

    func testFiresLowAtFivePercentRemaining() {
        let d = UsageAlertPolicy.decide(
            percentUsed: 95, windowSignature: "w1", priorSignature: "w1",
            firedThresholds: [25], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .low)
        XCTAssertEqual(d.fired, [25, 5])
    }

    func testFiresDepletedAtZeroRemaining() {
        let d = UsageAlertPolicy.decide(
            percentUsed: 100, windowSignature: "w1", priorSignature: "w1",
            firedThresholds: [25, 5], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .depleted)
        XCTAssertEqual(d.fired, [25, 5, 0])
    }

    func testPercentOverHundredTreatedAsDepleted() {
        let d = UsageAlertPolicy.decide(
            percentUsed: 130, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .depleted)
        XCTAssertEqual(d.fired, [25, 5, 0])
    }

    // MARK: - De-duplication

    func testDoesNotRefireAnAlreadyFiredThreshold() {
        // Still at 25% remaining and quarter already fired → silence.
        let d = UsageAlertPolicy.decide(
            percentUsed: 75, windowSignature: "w1", priorSignature: "w1",
            firedThresholds: [25], enabledThresholds: allEnabled)
        XCTAssertNil(d.fire)
        XCTAssertEqual(d.fired, [25])
    }

    func testRepeatedPollsAtSameLevelFireOnlyOnce() {
        var prior: UsageAlertPolicy.Decision?
        var fireCount = 0
        for _ in 0..<5 {
            let d = UsageAlertPolicy.decide(
                percentUsed: 96, windowSignature: "w1",
                priorSignature: prior?.signature,
                firedThresholds: prior?.fired ?? [],
                enabledThresholds: allEnabled)
            if d.fire != nil { fireCount += 1 }
            prior = d
        }
        // 96% used → 4% remaining crosses both 25 and 5; only the most severe
        // (low) fires, and only on the first poll.
        XCTAssertEqual(fireCount, 1)
    }

    // MARK: - Most-severe-only on a jump

    func testBigJumpFiresOnlyMostSevereButMarksAllCrossed() {
        // Jump from healthy straight to 2% remaining: crosses 25 and 5 at once.
        let d = UsageAlertPolicy.decide(
            percentUsed: 98, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .low)            // most severe newly-crossed
        XCTAssertEqual(d.fired, [25, 5])        // both marked, so neither re-fires
    }

    func testJumpToDepletedFiresDepletedOnly() {
        let d = UsageAlertPolicy.decide(
            percentUsed: 100, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .depleted)
        XCTAssertEqual(d.fired, [25, 5, 0])
    }

    // MARK: - Window reset re-arms

    func testNewWindowReArmsThresholds() {
        // Previous window had everything fired; a new signature clears them and
        // the current (low) level fires again.
        let d = UsageAlertPolicy.decide(
            percentUsed: 96, windowSignature: "w2", priorSignature: "w1",
            firedThresholds: [25, 5, 0], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .low)
        XCTAssertEqual(d.fired, [25, 5])
    }

    func testNewWindowWithHealthyUsageFiresNothing() {
        let d = UsageAlertPolicy.decide(
            percentUsed: 10, windowSignature: "w2", priorSignature: "w1",
            firedThresholds: [25, 5, 0], enabledThresholds: allEnabled)
        XCTAssertNil(d.fire)
        XCTAssertTrue(d.fired.isEmpty)
    }

    // MARK: - Disabled thresholds

    func testDisabledThresholdNeverFires() {
        // Only the depleted alert is enabled; at 25% remaining nothing fires.
        let d = UsageAlertPolicy.decide(
            percentUsed: 75, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: [.depleted])
        XCTAssertNil(d.fire)
        XCTAssertTrue(d.fired.isEmpty)
    }

    func testDisabledQuarterStillFiresLowWhenReached() {
        // Quarter off, low on. At 4% remaining, low fires and only low is marked.
        let d = UsageAlertPolicy.decide(
            percentUsed: 96, windowSignature: "w1", priorSignature: nil,
            firedThresholds: [], enabledThresholds: [.low, .depleted])
        XCTAssertEqual(d.fire, .low)
        XCTAssertEqual(d.fired, [5])
    }

    // MARK: - Window signature robustness (regression: notification flood)

    /// The reported reset time can jitter by a minute across polls
    /// ("9:59am" ↔ "10am" ↔ "10:01am"). Those must NOT produce different
    /// signatures, or the fired flags re-arm every poll and the user is flooded.
    func testMinuteJitterInResetTimeKeepsSameSignature() {
        // 9:59, 10:00, 10:01 on the same day — all within one rounded hour.
        let base = Date(timeIntervalSince1970: 1_800_000_000) // arbitrary fixed instant
        let nineFiftyNine = base.addingTimeInterval(-60)
        let ten = base
        let tenOhOne = base.addingTimeInterval(60)

        let s1 = UsageAlertPolicy.windowSignature(resetDate: nineFiftyNine, prior: nil)
        let s2 = UsageAlertPolicy.windowSignature(resetDate: ten, prior: s1)
        let s3 = UsageAlertPolicy.windowSignature(resetDate: tenOhOne, prior: s2)

        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s2, s3)
    }

    /// A single poll that fails to parse the reset clause (resetDate == nil)
    /// must inherit the prior window rather than mint a fresh "unknown" one,
    /// so a transient parse-miss can't re-arm and re-fire every threshold.
    func testTransientParseMissInheritsPriorSignature() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let good = UsageAlertPolicy.windowSignature(resetDate: reset, prior: nil)
        let miss = UsageAlertPolicy.windowSignature(resetDate: nil, prior: good)
        XCTAssertEqual(miss, good, "nil resetDate should carry the prior signature")
    }

    /// End-to-end: repeated polls where the signature flip-flops the way the CLI
    /// does in the wild (parsed → miss → parsed) must still fire exactly once.
    func testFlipFloppingResetDoesNotRefire() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        var prior: UsageAlertPolicy.Decision?
        var fireCount = 0

        // Alternate a valid reset date with a parse-miss (nil) across polls.
        let resetSequence: [Date?] = [reset, nil, reset, nil, reset, nil]
        for r in resetSequence {
            let signature = UsageAlertPolicy.windowSignature(resetDate: r, prior: prior?.signature)
            let d = UsageAlertPolicy.decide(
                percentUsed: 75, windowSignature: signature,
                priorSignature: prior?.signature,
                firedThresholds: prior?.fired ?? [],
                enabledThresholds: allEnabled)
            if d.fire != nil { fireCount += 1 }
            prior = d
        }
        XCTAssertEqual(fireCount, 1, "A flip-flopping reset signal must not re-notify")
    }

    /// A genuine new quota window (reset moved by days) must still re-arm once.
    func testGenuineNewWindowStillReArms() {
        let week1 = Date(timeIntervalSince1970: 1_800_000_000)
        let week2 = week1.addingTimeInterval(7 * 24 * 3600)
        let s1 = UsageAlertPolicy.windowSignature(resetDate: week1, prior: nil)
        let s2 = UsageAlertPolicy.windowSignature(resetDate: week2, prior: s1)
        XCTAssertNotEqual(s1, s2)

        let d = UsageAlertPolicy.decide(
            percentUsed: 75, windowSignature: s2, priorSignature: s1,
            firedThresholds: [25], enabledThresholds: allEnabled)
        XCTAssertEqual(d.fire, .quarter, "A real new window re-arms the quarter alert")
    }

    // MARK: - Reset alerts

    /// A fixed instant used as "now" so the tests are timezone/clock independent.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// First observation after launch: even if the reported reset already lies in
    /// the past (a reset happened while the app was closed), nothing fires — we
    /// only announce resets the running app actually witnesses.
    func testResetDoesNotFireOnFirstObservationOfPastReset() {
        let past = now.addingTimeInterval(-3600)
        let d = UsageAlertPolicy.decideReset(
            now: now, resetDate: past, percentUsed: 100, prior: .init())
        XCTAssertFalse(d.fireReset)
        // A past reset date doesn't arm a pending window.
        XCTAssertNil(d.state.pendingResetDate)
    }

    /// The core flow: observe a future reset while the window has some usage,
    /// then the reset time passes → fire exactly once.
    func testResetFiresOnceWhenUsedWindowRollsOver() {
        let reset = now.addingTimeInterval(1800)

        // Poll 1: window active in the future, some usage recorded.
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 100, prior: .init())
        XCTAssertFalse(d.fireReset)
        XCTAssertEqual(d.state.pendingResetDate, reset)
        XCTAssertTrue(d.state.didUse)

        // Poll 2: the reset time has passed (CLI now reports the fresh window).
        let after = reset.addingTimeInterval(60)
        let fresh = reset.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: fresh, percentUsed: 0, prior: d.state)
        XCTAssertTrue(d.fireReset)
        XCTAssertEqual(d.state.pendingResetDate, fresh)
        XCTAssertFalse(d.state.didUse, "fresh window starts clean")
    }

    /// Any usage counts, not just full depletion: a window that only reached
    /// 10% still announces when it resets.
    func testResetFiresForPartiallyUsedWindow() {
        let reset = now.addingTimeInterval(1800)
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 10, prior: .init())
        XCTAssertFalse(d.fireReset)
        XCTAssertTrue(d.state.didUse)

        let after = reset.addingTimeInterval(60)
        let fresh = reset.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: fresh, percentUsed: 0, prior: d.state)
        XCTAssertTrue(d.fireReset, "a partially-used window still announces its reset")
    }

    /// A completely untouched window (0% used) rolls over silently.
    func testResetDoesNotFireWhenWindowNeverUsed() {
        let reset = now.addingTimeInterval(1800)
        var d = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 0, prior: .init())
        XCTAssertFalse(d.fireReset)

        let after = reset.addingTimeInterval(60)
        d = UsageAlertPolicy.decideReset(
            now: after, resetDate: nil, percentUsed: 0, prior: d.state)
        XCTAssertFalse(d.fireReset, "no announcement for a window that was never used")
    }

    /// Once a reset has fired, subsequent polls in the fresh window don't re-fire.
    func testResetFiresOnlyOncePerRollover() {
        let reset = now.addingTimeInterval(1800)
        var state = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset, percentUsed: 100, prior: .init()).state

        var fireCount = 0
        // The rollover poll plus several steady polls afterward.
        let fresh = reset.addingTimeInterval(5 * 3600)
        var t = reset.addingTimeInterval(60)
        for _ in 0..<5 {
            let d = UsageAlertPolicy.decideReset(
                now: t, resetDate: fresh, percentUsed: 10, prior: state)
            if d.fireReset { fireCount += 1 }
            state = d.state
            t = t.addingTimeInterval(60)
        }
        XCTAssertEqual(fireCount, 1)
    }

    /// After a reset fires, if the fresh window is used again its own reset
    /// fires once more — the alert re-arms each window.
    func testResetReArmsForEachUsedWindow() {
        // Window 1 used then rolls over → fire #1.
        let reset1 = now.addingTimeInterval(1800)
        var state = UsageAlertPolicy.decideReset(
            now: now, resetDate: reset1, percentUsed: 100, prior: .init()).state

        let reset2 = reset1.addingTimeInterval(5 * 3600)
        var d = UsageAlertPolicy.decideReset(
            now: reset1.addingTimeInterval(60), resetDate: reset2, percentUsed: 0, prior: state)
        XCTAssertTrue(d.fireReset)
        state = d.state

        // Window 2 gets used too.
        state = UsageAlertPolicy.decideReset(
            now: reset1.addingTimeInterval(3600), resetDate: reset2, percentUsed: 100, prior: state).state

        // Window 2 rolls over → fire #2.
        let reset3 = reset2.addingTimeInterval(5 * 3600)
        d = UsageAlertPolicy.decideReset(
            now: reset2.addingTimeInterval(60), resetDate: reset3, percentUsed: 0, prior: state)
        XCTAssertTrue(d.fireReset, "a second used window announces its own reset")
    }
}
