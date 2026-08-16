import XCTest
import Carbon.HIToolbox
@testable import halfFull

final class TargetModeTests: XCTestCase {
    func testBothTargetsAreAvailable() {
        XCTAssertEqual(TargetMode.allCases, [.focusedText, .clipboard])
    }

    func testFocusedTextDefaultsToOptionF() {
        XCTAssertEqual(TargetMode.focusedText.defaultHotKey,
                       HotKey(keyCode: UInt32(kVK_ANSI_F),
                              carbonModifiers: UInt32(optionKey)))
    }

    func testClipboardDefaultsToOptionA() {
        XCTAssertEqual(TargetMode.clipboard.defaultHotKey,
                       HotKey(keyCode: UInt32(kVK_ANSI_A),
                              carbonModifiers: UInt32(optionKey)))
    }

    func testTargetsUseDistinctCarbonIDs() {
        XCTAssertNotEqual(TargetMode.focusedText.hotKeyID, TargetMode.clipboard.hotKeyID)
    }
}
