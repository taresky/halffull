import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+).
/// The legacy `SMLoginItemSetEnabled` flow required a helper bundle; mainApp does not.
enum LaunchAtLoginManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns `true` on success, `false` on failure (e.g. the user denied the request
    /// from System Settings → General → Login Items). Errors are logged but not thrown
    /// so callers can keep the UI in sync with the post-attempt `isEnabled`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, .enabled):
                return true
            case (true, _):
                try service.register()
                return service.status == .enabled
            case (false, .notRegistered), (false, .notFound):
                return true
            case (false, _):
                try service.unregister()
                return service.status != .enabled
            }
        } catch {
            NSLog("halfFull: LaunchAtLogin toggle failed — \(error.localizedDescription)")
            return false
        }
    }
}
