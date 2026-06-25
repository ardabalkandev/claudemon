import XCTest
@testable import ClaudemonCore

/// Tests for the timezone-aware 24-hour clock formatter used by the floating
/// widget footer's "resets at HH:mm" suffix. All cases are deterministic: the
/// Date is built from a fixed epoch and an explicit TimeZone is supplied, so
/// results never depend on the host machine's locale or timezone.
final class UsageFormattingResetTests: XCTestCase {

    /// 2026-06-28 20:20:00 UTC.
    private let fixedDate = Date(timeIntervalSince1970: 1_782_678_000)

    func testShortClockStringInIstanbul() {
        // Istanbul is UTC+3 in June: 20:20 UTC -> 23:20.
        let tz = TimeZone(identifier: "Europe/Istanbul")
        XCTAssertEqual(UsageFormatting.shortClockString(fixedDate, timeZone: tz), "23:20")
    }

    func testShortClockStringInNewYork() {
        // New York is UTC-4 (EDT) in June: 20:20 UTC -> 16:20.
        let tz = TimeZone(identifier: "America/New_York")
        XCTAssertEqual(UsageFormatting.shortClockString(fixedDate, timeZone: tz), "16:20")
    }

    func testShortClockStringIsZeroPaddedAcrossMidnight() {
        // 2026-06-28 23:05:00 UTC -> Tokyo (UTC+9) is 08:05 next day.
        let date = Date(timeIntervalSince1970: 1_782_687_900)
        let tz = TimeZone(identifier: "Asia/Tokyo")
        XCTAssertEqual(UsageFormatting.shortClockString(date, timeZone: tz), "08:05")
    }

    func testNilTimeZoneFallsBackToCurrent() {
        // A nil timezone must behave exactly like the existing zero-arg helper,
        // which formats in the current timezone.
        XCTAssertEqual(
            UsageFormatting.shortClockString(fixedDate, timeZone: nil),
            UsageFormatting.shortClockString(fixedDate)
        )
    }
}
