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
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 4)
        XCTAssertEqual(
            MenuBarDisplayMode.allCases,
            [.iconAndText, .textOnly, .iconOnly, .bars],
            "Order is user-facing (drives the settings Picker) — pin it down"
        )
    }

    // MARK: - MenuBarBarsView.Configuration

    func testBarsConfigurationEquatableCoversAllFields() {
        let base = MenuBarBarsView.Configuration(
            sessionPercent: 40, weekPercent: 20, showsPercent: true, isVertical: false)
        XCTAssertEqual(base, MenuBarBarsView.Configuration(
            sessionPercent: 40, weekPercent: 20, showsPercent: true, isVertical: false))

        XCTAssertFalse(base.preciseFill, "preciseFill must default to false")
        XCTAssertFalse(base.halfWidthBars, "halfWidthBars must default to false")

        // Each field independently participates in equality — the app relies
        // on this to know when the menu-bar raster must change.
        var changed = base
        changed.sessionPercent = 41
        XCTAssertNotEqual(base, changed)

        changed = base
        changed.weekPercent = nil
        XCTAssertNotEqual(base, changed)

        changed = base
        changed.showsPercent = false
        XCTAssertNotEqual(base, changed)

        changed = base
        changed.isVertical = true
        XCTAssertNotEqual(base, changed)

        changed = base
        changed.preciseFill = true
        XCTAssertNotEqual(base, changed)

        changed = base
        changed.halfWidthBars = true
        XCTAssertNotEqual(base, changed)
    }

    // MARK: - PreciseBarsPreference

    func testPreciseBarsPreferenceRoundTripsAndDefaultsToFalse() throws {
        let suiteName = "test.claudemon.preciseBars"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertFalse(PreciseBarsPreference.read(from: defaults),
                       "absent key must read as false (the default style)")
        PreciseBarsPreference.write(true, to: defaults)
        XCTAssertTrue(PreciseBarsPreference.read(from: defaults))
        PreciseBarsPreference.write(false, to: defaults)
        XCTAssertFalse(PreciseBarsPreference.read(from: defaults))

        // A nil suite (unresolvable container) must fail soft to false.
        XCTAssertFalse(PreciseBarsPreference.read(from: nil))
    }
}
