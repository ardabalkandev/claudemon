import XCTest
@testable import ClaudemonCore

/// Unit tests for the pure value-level logic in `MenuBarMiniBar.swift`: the
/// `MenuBarDisplayMode` enum that drives the menu-bar label presentation.
final class MenuBarMiniBarTests: XCTestCase {

    // MARK: - MenuBarDisplayMode rawValue round-trip

    func testDisplayModeRawValueRoundTrips() {
        for mode in MenuBarDisplayMode.allCases {
            XCTAssertEqual(
                MenuBarDisplayMode(rawValue: mode.rawValue),
                mode,
                "rawValue round-trip must reconstruct the same case (persistence relies on this)"
            )
        }
    }

    func testDisplayModeRejectsUnknownRawValue() {
        XCTAssertNil(MenuBarDisplayMode(rawValue: "notAMode"))
        XCTAssertNil(MenuBarDisplayMode(rawValue: ""))
        // A removed/unknown rawValue must no longer resolve, so persisted old
        // bar values fall back to the default at the call site.
        XCTAssertNil(MenuBarDisplayMode(rawValue: "removedLegacyMode"))
    }

    func testDisplayModeIdMatchesRawValue() {
        for mode in MenuBarDisplayMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    // MARK: - MenuBarDisplayMode allCases count + order

    func testDisplayModeCaseCountAndOrder() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 3)
        XCTAssertEqual(
            MenuBarDisplayMode.allCases,
            [.iconAndText, .textOnly, .iconOnly],
            "Order is user-facing (drives the settings Picker) — pin it down"
        )
    }
}
