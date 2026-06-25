import XCTest
@testable import Claudemon

/// Unit tests for the minimal `major.minor.patch` `SemVer` used by the
/// "Check for Updates" comparison in `UpdateChecker`. These pin down parsing
/// (leading-`v` strip, missing components) and ordering semantics so a future
/// refactor of the update path can't silently break version comparison.
final class SemVerTests: XCTestCase {

    // MARK: - Ordering

    func testPatchOrdering() throws {
        let lower = try XCTUnwrap(SemVer("1.1.2"))
        let higher = try XCTUnwrap(SemVer("1.1.3"))
        XCTAssertTrue(lower < higher, "1.1.2 < 1.1.3")
        XCTAssertFalse(higher < lower)
    }

    func testMinorOutranksPatch() throws {
        let v120 = try XCTUnwrap(SemVer("1.2.0"))
        let v119 = try XCTUnwrap(SemVer("1.1.9"))
        XCTAssertTrue(v120 > v119, "1.2.0 > 1.1.9 (a higher minor beats a higher patch)")
    }

    // MARK: - Leading `v` strip

    func testLeadingVIsStripped() throws {
        let tagged = try XCTUnwrap(SemVer("v1.1.2"))
        let plain = try XCTUnwrap(SemVer("1.1.2"))
        XCTAssertEqual(tagged, plain, "v1.1.2 == 1.1.2")
        XCTAssertEqual(tagged.description, "1.1.2")
    }

    func testUppercaseLeadingVIsStripped() throws {
        let tagged = try XCTUnwrap(SemVer("V2.0.1"))
        XCTAssertEqual(tagged, try XCTUnwrap(SemVer("2.0.1")))
    }

    // MARK: - Missing components default to zero

    func testMissingPatchDefaultsToZero() throws {
        let short = try XCTUnwrap(SemVer("1.1"))
        let full = try XCTUnwrap(SemVer("1.1.0"))
        XCTAssertEqual(short, full, "1.1 == 1.1.0")
    }

    func testMissingMinorAndPatchStillOrders() throws {
        let major = try XCTUnwrap(SemVer("2"))
        let lower = try XCTUnwrap(SemVer("1.9.9"))
        XCTAssertTrue(major > lower, "2 > 1.9.9 (2 parses as 2.0.0)")
        XCTAssertEqual(major.description, "2.0.0")
    }

    // MARK: - Equality

    func testEqualVersionsAreNotOrdered() throws {
        let a = try XCTUnwrap(SemVer("1.1.2"))
        let b = try XCTUnwrap(SemVer("1.1.2"))
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
    }

    // MARK: - Rejects non-numeric / empty input

    func testNonNumericComponentFailsToParse() {
        XCTAssertNil(SemVer("1.x.0"), "Non-numeric components must not parse")
        XCTAssertNil(SemVer(""), "Empty string must not parse")
    }
}
