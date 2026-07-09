import XCTest
@testable import halfFull

final class ConversionPolicyTests: XCTestCase {

    func testUntrustedAlwaysRequiresTrust() {
        // field result must not matter — we never touch the field without trust
        XCTAssertEqual(ConversionPolicy.plan(.untrusted), .requireTrust)
    }

    func testApplied() {
        XCTAssertEqual(ConversionPolicy.plan(.edited(.applied)), .applied)
    }

    func testNoChange() {
        XCTAssertEqual(ConversionPolicy.plan(.edited(.noChange)), .noChange)
    }

    func testNotFocused() {
        XCTAssertEqual(ConversionPolicy.plan(.edited(.notFocused)), .notFocused)
    }

    func testUnreadable() {
        XCTAssertEqual(ConversionPolicy.plan(.edited(.unreadable)), .unreadable)
    }

    func testBusyIsSilent() {
        XCTAssertEqual(ConversionPolicy.plan(.edited(.busy)), .silent)
    }
}
