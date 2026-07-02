import XCTest
import Carbon
@testable import halfFull

final class LaunchReasonTests: XCTestCase {

    // MARK: - Apple Event available (authoritative signal)

    func testOpenEventWithLoginItemFlagIsLoginLaunch() {
        XCTAssertTrue(LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: true),
                                                     systemUptime: 5000,
                                                     isLoginItemRegistered: false))
    }

    func testOpenEventWithoutFlagIsManualEvenRightAfterBoot() {
        // The exact hole the old heuristic had: manual open < 90 s after boot
        // while registered as a login item must still show the window.
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: false),
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: true))
    }

    func testNonOpenEventIsManual() {
        let quit = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: quit,
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: true))
    }

    // MARK: - No event → legacy uptime heuristic

    func testNoEventEarlyUptimeRegisteredFallsBackToLoginHeuristic() {
        XCTAssertTrue(LaunchReason.isLoginItemLaunch(event: nil,
                                                     systemUptime: 30,
                                                     isLoginItemRegistered: true))
    }

    func testNoEventLateUptimeIsManual() {
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: nil,
                                                      systemUptime: 300,
                                                      isLoginItemRegistered: true))
    }

    func testNoEventNotRegisteredIsManual() {
        XCTAssertFalse(LaunchReason.isLoginItemLaunch(event: nil,
                                                      systemUptime: 30,
                                                      isLoginItemRegistered: false))
    }

    // MARK: - Helpers

    private func openEvent(loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        if loginItem {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                           forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }
}
