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
}
