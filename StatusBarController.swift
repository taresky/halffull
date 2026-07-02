import Cocoa

/// Owns the menu-bar `NSStatusItem`. Builds a compact menu with:
///   • Show Window   — opens the main UI (settings + quick-convert + hotkey)
///   • Convert       — fires the hotkey action via menu (for users who forget the binding)
///   • Force half→full / full→half
///   • About
///   • Quit
///
/// The "Preferences…" entry is gone — settings now live inside the main window.
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let showMainWindowHandler: () -> Void
    private let openAboutHandler: () -> Void

    init(showMainWindow: @escaping () -> Void, openAbout: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.showMainWindowHandler = showMainWindow
        self.openAboutHandler = openAbout
        super.init()

        configureButton()
        statusItem.menu = buildMenu()

        // Our pref is the single source of truth for visibility. AppKit also
        // persists isVisible under its own defaults key (per autosaveName);
        // this unconditional assignment overrides whatever it restored.
        statusItem.isVisible = PreferencesStore.shared.showMenuBarIcon

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleHotKeyChanged),
                                               name: PreferencesStore.hotKeyChangedNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMenuBarIconChanged),
                                               name: PreferencesStore.menuBarIconChangedNotification,
                                               object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func refresh() { statusItem.menu = buildMenu() }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // SF Symbol — auto template image, follows menu-bar tint, has Dark Mode variants.
        // `textformat.size` is literally "Aa" — same visual idiom as the app icon.
        if let image = NSImage(systemSymbolName: "textformat.size",
                               accessibilityDescription: Bundle.main.appName) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Aa"
        }
        button.toolTip = NSLocalizedString("statusbar.tooltip",
                                           value: "halfFull — switch text width",
                                           comment: "")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let prefs = PreferencesStore.shared

        // 1. Show Window — the primary entry now that settings live in the main UI.
        let show = NSMenuItem(title: NSLocalizedString("menu.showWindow",
                                                       value: "Show Window",
                                                       comment: ""),
                              action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        // 2. Convert action — shows the bound hotkey trailing for muscle-memory training.
        let convertTitle = String(format: NSLocalizedString("menu.convert",
                                                            value: "Convert (%@)",
                                                            comment: ""),
                                  ModifierTranslator.symbolicDescription(
                                    carbonModifiers: prefs.hotKeyCarbonModifiers,
                                    keyCode: prefs.hotKeyKeyCode))
        let convert = NSMenuItem(title: convertTitle,
                                 action: #selector(convertPreferred),
                                 keyEquivalent: "")
        convert.target = self
        menu.addItem(convert)

        let toFull = NSMenuItem(title: NSLocalizedString("menu.forceFullWidth",
                                                         value: "Force half → full-width",
                                                         comment: ""),
                                action: #selector(forceFullWidth), keyEquivalent: "")
        toFull.target = self
        menu.addItem(toFull)

        let toHalf = NSMenuItem(title: NSLocalizedString("menu.forceHalfWidth",
                                                         value: "Force full → half-width",
                                                         comment: ""),
                                action: #selector(forceHalfWidth), keyEquivalent: "")
        toHalf.target = self
        menu.addItem(toHalf)

        menu.addItem(.separator())

        let about = NSMenuItem(title: NSLocalizedString("menu.about",
                                                        value: "About halfFull",
                                                        comment: ""),
                               action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: NSLocalizedString("menu.quit", value: "Quit", comment: ""),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func showWindow()        { showMainWindowHandler() }
    @objc private func convertPreferred()  { ConversionController.shared.trigger() }
    @objc private func forceFullWidth()    { ConversionController.shared.trigger(directionOverride: .toFullWidth, scopeOverride: nil) }
    @objc private func forceHalfWidth()    { ConversionController.shared.trigger(directionOverride: .toHalfWidth, scopeOverride: nil) }
    @objc private func openAbout()         { openAboutHandler() }
    @objc private func quit()              { NSApp.terminate(nil) }
    @objc private func handleHotKeyChanged() { refresh() }

    @objc private func handleMenuBarIconChanged() {
        statusItem.isVisible = PreferencesStore.shared.showMenuBarIcon
    }
}
