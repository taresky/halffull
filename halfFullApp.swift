import Cocoa
import SwiftUI
import ServiceManagement

/// Pure-AppKit entry point. We deliberately do NOT use SwiftUI's `App` protocol —
/// any SwiftUI `Settings { ... }` or `WindowGroup { ... }` scene becomes part of
/// the app's restorable state, and macOS will helpfully re-show whichever
/// SwiftUI windows were open the last time the app quit. That's how we ended up
/// with a stray empty "halfFull Settings" window appearing on launch.
///
/// Pure NSApplicationDelegate + NSWindow lifecycle gives us full control.
@main
final class HalfFullMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusBar: StatusBarController!
    private var mainWindowController: MainWindowController?

    // We explicitly switched to .regular to show a window — used to suppress the
    // launch-to-convert path on subsequent activations (kept for compatibility
    // even though the legacy launch-to-convert flow is gone in v3+; harmless).
    private var showingMainWindow = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally NOT requesting notification authorization here —
        // a fresh install shouldn't pop any system dialogs except the
        // Accessibility one (which the user must grant for the hotkey to
        // work at all). Notification permission is requested lazily, only
        // when the user toggles "Show notifications" ON.
        _ = NotificationPresenter.shared

        // Build the system menu bar. Pure-AppKit @main with no XIB means
        // we get NO menu bar by default — so ⌘Q, ⌘H, ⌘W, the standard
        // Edit-menu items (Cut/Copy/Paste/Select All), and ⌘, wouldn't fire.
        // Build it programmatically and assign to NSApp.mainMenu.
        installMainMenu()

        statusBar = StatusBarController(
            showMainWindow: { [weak self] in self?.showMainWindow() },
            openAbout:      { [weak self] in self?.showMainWindow(selectingAboutTab: true) }
        )

        registerHotKey()
        observeHotKeyChanges()

        if shouldOpenMainWindowOnLaunch() {
            showMainWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        // Stale-grant auto-recovery on launch:
        //   • If currently trusted → set the sticky bit (so future updates can
        //     recognize the "was granted, now stale" state). This runs even
        //     when the user only uses the menu bar and never opens the window.
        //   • If sticky bit is set AND not currently trusted → typical
        //     ad-hoc-update breakage. Auto-fire the system prompt + open
        //     System Settings so the user lands exactly where they need to be.
        // Deferred to next runloop turn so AppKit is fully up; the AX prompt
        // needs a parent app context to render in-context.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AccessibilityHelper.shared.isTrusted {
                PreferencesStore.shared.hasGrantedAXBefore = true
            } else if PreferencesStore.shared.hasGrantedAXBefore {
                AccessibilityHelper.shared.ensureTrustedPrompt()
                AccessibilityHelper.shared.openAccessibilitySettings()
            }
        }
    }

    // MARK: - Menu bar

    private func installMainMenu() {
        let appName = Bundle.main.appName
        let mainMenu = NSMenu()

        // Application menu — title is hidden by macOS (it shows the running
        // app's bundle name automatically), so we leave the NSMenuItem
        // title blank and only fill the submenu.
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(item("About \(appName)", target: self,
                             action: #selector(menuShowMainWindow), key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", target: self,
                             action: #selector(menuShowMainWindow), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(appName)", target: nil,
                             action: #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", target: nil,
                              action: #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(item("Show All", target: nil,
                             action: #selector(NSApplication.unhideAllApplications(_:)), key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(appName)", target: nil,
                             action: #selector(NSApplication.terminate(_:)), key: "q"))

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit — standard items wired via responder-chain selectors so the
        // active text field in the Settings window picks them up.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", target: nil, action: Selector(("undo:")), key: "z"))
        let redo = item("Redo", target: nil, action: Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", target: nil, action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("Copy", target: nil, action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("Paste", target: nil, action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("Select All", target: nil, action: #selector(NSText.selectAll(_:)), key: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window — Minimize / Zoom / Bring All to Front.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", target: nil,
                                action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item("Zoom", target: nil,
                                action: #selector(NSWindow.performZoom(_:)), key: ""))
        windowMenu.addItem(item("Close", target: nil,
                                action: #selector(NSWindow.performClose(_:)), key: "w"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", target: nil,
                                action: #selector(NSApplication.arrangeInFront(_:)), key: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// Small helper to keep the menu construction readable.
    private func item(_ title: String, target: AnyObject?, action: Selector?, key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = target
        return mi
    }

    @objc private func menuShowMainWindow() {
        showMainWindow()
    }

    /// Disable secure state restoration: nothing in this app benefits from
    /// macOS auto-reopening windows on next launch, and the SwiftUI Settings
    /// scene's restoration was the source of the v3.1 empty-window bug.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    private func shouldOpenMainWindowOnLaunch() -> Bool {
        // Within the first 90 s of system uptime AND registered as a Login Item ⇒
        // treat as a "user just logged in" launch and stay silent in the menu bar.
        // Anything else (Finder/Spotlight/manual launch) → show the window.
        let uptime = ProcessInfo.processInfo.systemUptime
        let isLoginItemRegistered = SMAppService.mainApp.status == .enabled
        let looksLikeLoginLaunch = uptime < 90 && isLoginItemRegistered
        return !looksLikeLoginLaunch
    }

    /// Dock-click / Cmd+Tab when no window is visible — reopen the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        let prefs = PreferencesStore.shared
        HotKeyManager.shared.register(keyCode: prefs.hotKeyKeyCode,
                                      carbonModifiers: prefs.hotKeyCarbonModifiers) {
            ConversionController.shared.trigger()
        }
    }

    private func observeHotKeyChanges() {
        NotificationCenter.default.addObserver(forName: PreferencesStore.hotKeyChangedNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKey()
        }
    }

    // MARK: - Main window

    func showMainWindow(selectingAboutTab: Bool = false) {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
            mainWindowController?.window?.delegate = self
        }
        NSApp.setActivationPolicy(.regular)
        showingMainWindow = true

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        _ = selectingAboutTab  // v3.1 collapsed tabs; About is always visible at the bottom.
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === mainWindowController?.window else { return }
        showingMainWindow = false
        // Defer the policy switch so AppKit finishes the close animation first.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
