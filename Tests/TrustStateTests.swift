import XCTest
@testable import halfFull

final class TrustStateTests: XCTestCase {

    func testTrustedIsGrantedEvenIfNeverSeenBefore() {
        XCTAssertEqual(TrustState.derive(isTrusted: true, hasGrantedBefore: false),
                       .granted)
    }

    func testUntrustedWithStickyBitIsStaleGrant() {
        XCTAssertEqual(TrustState.derive(isTrusted: false, hasGrantedBefore: true),
                       .staleGrant)
    }

    func testUntrustedWithoutStickyBitIsFreshNeed() {
        XCTAssertEqual(TrustState.derive(isTrusted: false, hasGrantedBefore: false),
                       .freshNeed)
    }
}
