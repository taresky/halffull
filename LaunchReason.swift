import Cocoa
import Carbon

/// Decides whether this process launch was initiated by the system as a
/// login item (→ stay silent in the menu bar) rather than by the user
/// (→ show the main window).
///
/// Primary signal: the launching Apple Event. SMAppService login-item
/// launches carry `keyAELaunchedAsLogInItem` in the `kAEOpenApplication`
/// event's `keyAEPropData` parameter — a manual Finder/Spotlight launch
/// produces an `oapp` event WITHOUT that flag, even seconds after login.
///
/// Fallback (no event to inspect): the legacy heuristic — within 90 s of
/// boot AND registered as a login item ⇒ assume login launch.
enum LaunchReason {

    static func isLoginItemLaunch(event: NSAppleEventDescriptor?,
                                  systemUptime: TimeInterval,
                                  isLoginItemRegistered: Bool) -> Bool {
        guard let event else {
            return systemUptime < 90 && isLoginItemRegistered
        }
        guard event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              let propData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return propData.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
