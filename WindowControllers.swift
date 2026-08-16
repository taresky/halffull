import Cocoa
import SwiftUI

/// Single visible, target-mode settings window.
/// We use an explicit NSWindowController (rather than the SwiftUI Settings/WindowGroup
/// scenes) so we keep full control over activation policy and Dock-icon visibility.
final class MainWindowController: NSWindowController {

    convenience init() {
        let hosting = NSHostingController(rootView: MainView())
        let window = NSWindow(contentViewController: hosting)
        window.title = Bundle.main.appName
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.center()
        self.init(window: window)
    }
}
