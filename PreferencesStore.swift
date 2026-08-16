import Cocoa
import Combine
import Carbon.HIToolbox

/// Centralized, observable preferences backed by `UserDefaults`.
/// SwiftUI binds to it via `@ObservedObject`; AppKit reads via the typed properties.
///
/// Adding a new preference is two lines: a key, and a `@Pref(...)` declaration.
final class PreferencesStore: ObservableObject {

    static let shared = PreferencesStore()

    /// Posted (in addition to `objectWillChange`) when the hotkey binding changes,
    /// so `HotKeyManager` can re-register without subscribing to Combine.
    static let hotKeyChangedNotification = Notification.Name("FWCHotKeyChanged")

    /// Posted (in addition to `objectWillChange`) when the menu-bar-icon pref
    /// changes, so `StatusBarController` can re-sync without Combine.
    static let menuBarIconChangedNotification = Notification.Name("FWCMenuBarIconChanged")

    // MARK: - Keys (single source of truth — never literal-stringify outside this enum)

    private enum Key {
        static let hotKeyKeyCode = "hotKey.keyCode"
        static let hotKeyCarbonModifiers = "hotKey.carbonModifiers"
        static let clipboardHotKeyKeyCode = "hotKey.clipboard.keyCode"
        static let clipboardHotKeyCarbonModifiers = "hotKey.clipboard.carbonModifiers"
        static let conversionDirection = "conversion.direction"
        static let conversionScope = "conversion.scope"
        static let plainClipTrimTrailingLineWhitespace = "plainClip.trimTrailingLineWhitespace"
        static let plainClipTrimLeadingLineWhitespace = "plainClip.trimLeadingLineWhitespace"
        static let plainClipTrimWholeString = "plainClip.trimWholeString"
        static let plainClipRemoveInvisibleCharacters = "plainClip.removeInvisibleCharacters"
        static let plainClipRemoveLineBreaks = "plainClip.removeLineBreaks"
        static let plainClipRemoveBlankLines = "plainClip.removeBlankLines"
        static let plainClipCollapseSpaces = "plainClip.collapseSpaces"
        static let plainClipReplaceTabs = "plainClip.replaceTabs"
        static let plainClipConvertToASCII = "plainClip.convertToASCII"
        static let plainClipStraightenQuotes = "plainClip.straightenQuotes"
        static let plainClipNormalizeUnicode = "plainClip.normalizeUnicode"
        static let plainClipPasteAfterCleaning = "plainClip.pasteAfterCleaning"
        static let restoreClipboard = "behavior.restoreClipboard"
        static let convertSpaceToIdeographic = "behavior.convertSpaceToIdeographic"
        static let playSoundOnSuccess = "behavior.playSoundOnSuccess"
        static let showNotifications = "behavior.showNotifications"
        static let launchAtLogin = "behavior.launchAtLogin"
        static let showMenuBarIcon = "behavior.showMenuBarIcon"
        static let hasCompletedOnboarding = "onboarding.completed"
        static let hasGrantedAXBefore = "ax.hasGrantedBefore"
    }

    private let defaults = UserDefaults.standard

    private init() {
        // Defaults are registered (not set) so the user's explicit values win.
        defaults.register(defaults: [
            Key.hotKeyKeyCode: HotKey.defaultBinding.keyCode,
            Key.hotKeyCarbonModifiers: HotKey.defaultBinding.carbonModifiers,
            Key.clipboardHotKeyKeyCode: TargetMode.clipboard.defaultHotKey.keyCode,
            Key.clipboardHotKeyCarbonModifiers: TargetMode.clipboard.defaultHotKey.carbonModifiers,
            Key.conversionDirection: ConversionDirection.smart.rawValue,
            Key.conversionScope: ConversionScope.all.rawValue,
            Key.plainClipTrimTrailingLineWhitespace: false,
            Key.plainClipTrimLeadingLineWhitespace: false,
            Key.plainClipTrimWholeString: false,
            Key.plainClipRemoveInvisibleCharacters: false,
            Key.plainClipRemoveLineBreaks: false,
            Key.plainClipRemoveBlankLines: false,
            Key.plainClipCollapseSpaces: false,
            Key.plainClipReplaceTabs: false,
            Key.plainClipConvertToASCII: false,
            Key.plainClipStraightenQuotes: false,
            Key.plainClipNormalizeUnicode: false,
            Key.plainClipPasteAfterCleaning: false,
            Key.restoreClipboard: true,
            Key.convertSpaceToIdeographic: true,
            Key.playSoundOnSuccess: false,
            Key.showNotifications: true,
            Key.launchAtLogin: false,
            Key.showMenuBarIcon: true,
            Key.hasCompletedOnboarding: false,
            Key.hasGrantedAXBefore: false,
        ])

        // Migration guard: an existing halfFull user may already have chosen
        // Option-A for focused text before the clipboard target existed. Keep
        // their binding and give the new target a non-conflicting fallback.
        let focused = hotKey
        let clipboard = hotKey(for: .clipboard)
        if focused == clipboard {
            let fallback = HotKey(
                keyCode: UInt32(kVK_ANSI_A),
                carbonModifiers: UInt32(optionKey | shiftKey)
            )
            defaults.set(Int(fallback.keyCode), forKey: Key.clipboardHotKeyKeyCode)
            defaults.set(Int(fallback.carbonModifiers),
                         forKey: Key.clipboardHotKeyCarbonModifiers)
        }
    }

    // MARK: - Hotkey
    //
    // Multi-key + extra notification — stays hand-written so both axes write once.

    var hotKey: HotKey {
        get {
            HotKey(keyCode: UInt32(defaults.integer(forKey: Key.hotKeyKeyCode)),
                   carbonModifiers: UInt32(defaults.integer(forKey: Key.hotKeyCarbonModifiers)))
        }
        set { _ = setHotKey(newValue) }
    }

    /// Atomic setter — writes both axes, fires `objectWillChange` and
    /// `hotKeyChangedNotification` exactly once.
    @discardableResult
    func setHotKey(_ hotKey: HotKey) -> Bool {
        setHotKey(hotKey, for: .focusedText)
    }

    func hotKey(for mode: TargetMode) -> HotKey {
        switch mode {
        case .focusedText:
            return hotKey
        case .clipboard:
            return HotKey(
                keyCode: UInt32(defaults.integer(forKey: Key.clipboardHotKeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.clipboardHotKeyCarbonModifiers))
            )
        }
    }

    /// Atomic, target-aware setter. The notification carries the changed mode
    /// so AppKit listeners can update only the corresponding registration.
    @discardableResult
    func setHotKey(_ hotKey: HotKey, for mode: TargetMode) -> Bool {
        let otherMode: TargetMode = mode == .focusedText ? .clipboard : .focusedText
        guard self.hotKey(for: otherMode) != hotKey else { return false }

        objectWillChange.send()
        switch mode {
        case .focusedText:
            defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyKeyCode)
            defaults.set(Int(hotKey.carbonModifiers), forKey: Key.hotKeyCarbonModifiers)
        case .clipboard:
            defaults.set(Int(hotKey.keyCode), forKey: Key.clipboardHotKeyKeyCode)
            defaults.set(Int(hotKey.carbonModifiers), forKey: Key.clipboardHotKeyCarbonModifiers)
        }
        NotificationCenter.default.post(name: Self.hotKeyChangedNotification, object: mode)
        return true
    }

    // MARK: - Conversion
    //
    // `@Pref` fires `objectWillChange` BEFORE writing to `defaults`, matching the
    // ObservableObject contract (mirrors @Published's willSet semantics — observers
    // that snap the old value via `objectWillChange.sink { ... }` see the pre-change
    // state, not the post-change one).

    @Pref(Key.conversionDirection, fallback: .smart)
    var conversionDirection: ConversionDirection

    @Pref(Key.conversionScope, fallback: .all)
    var conversionScope: ConversionScope

    // MARK: - Plain Clip

    @Pref(Key.plainClipTrimTrailingLineWhitespace)
    var plainClipTrimTrailingLineWhitespace: Bool

    @Pref(Key.plainClipTrimLeadingLineWhitespace)
    var plainClipTrimLeadingLineWhitespace: Bool

    @Pref(Key.plainClipTrimWholeString)
    var plainClipTrimWholeString: Bool

    @Pref(Key.plainClipRemoveInvisibleCharacters)
    var plainClipRemoveInvisibleCharacters: Bool

    @Pref(Key.plainClipRemoveLineBreaks)
    var plainClipRemoveLineBreaks: Bool

    @Pref(Key.plainClipRemoveBlankLines)
    var plainClipRemoveBlankLines: Bool

    @Pref(Key.plainClipCollapseSpaces)
    var plainClipCollapseSpaces: Bool

    @Pref(Key.plainClipReplaceTabs)
    var plainClipReplaceTabs: Bool

    @Pref(Key.plainClipConvertToASCII)
    var plainClipConvertToASCII: Bool

    @Pref(Key.plainClipStraightenQuotes)
    var plainClipStraightenQuotes: Bool

    @Pref(Key.plainClipNormalizeUnicode)
    var plainClipNormalizeUnicode: Bool

    @Pref(Key.plainClipPasteAfterCleaning)
    var plainClipPasteAfterCleaning: Bool

    var plainClipOptions: PlainTextCleaner.Options {
        PlainTextCleaner.Options(
            trimTrailingLineWhitespace: plainClipTrimTrailingLineWhitespace,
            trimLeadingLineWhitespace: plainClipTrimLeadingLineWhitespace,
            trimWholeString: plainClipTrimWholeString,
            removeInvisibleCharacters: plainClipRemoveInvisibleCharacters,
            removeLineBreaks: plainClipRemoveLineBreaks,
            removeBlankLines: plainClipRemoveBlankLines,
            collapseSpaces: plainClipCollapseSpaces,
            replaceTabs: plainClipReplaceTabs,
            convertToASCII: plainClipConvertToASCII,
            straightenQuotes: plainClipStraightenQuotes,
            normalizeUnicode: plainClipNormalizeUnicode
        )
    }

    // MARK: - Behavior toggles

    @Pref(Key.restoreClipboard)
    var restoreClipboard: Bool

    @Pref(Key.convertSpaceToIdeographic)
    var convertSpaceToIdeographic: Bool

    @Pref(Key.playSoundOnSuccess)
    var playSoundOnSuccess: Bool

    @Pref(Key.showNotifications)
    var showNotifications: Bool

    @Pref(Key.launchAtLogin)
    var launchAtLogin: Bool

    @Pref(Key.showMenuBarIcon, notification: PreferencesStore.menuBarIconChangedNotification)
    var showMenuBarIcon: Bool

    @Pref(Key.hasCompletedOnboarding)
    var hasCompletedOnboarding: Bool

    /// Sticky bit: flipped to `true` the first time we observe a successful
    /// `AXIsProcessTrusted == true`. Never cleared. Used to distinguish
    /// "fresh install, user hasn't granted yet" from "granted before, but TCC
    /// lost the grant after an ad-hoc-signed update." The latter case triggers
    /// the in-app recovery flow.
    @Pref(Key.hasGrantedAXBefore)
    var hasGrantedAXBefore: Bool
}

// MARK: - @Pref

/// UserDefaults-backed property wrapper that centralises the send-then-set ritual.
///
/// Uses the enclosing-instance subscript so setters fire `objectWillChange` on the
/// parent `PreferencesStore` before writing — same ordering as hand-written setters
/// and as `@Published`. Optional `notification` posts an extra `Notification.Name`
/// for AppKit listeners that don't subscribe to Combine.
///
/// Interface is unchanged: callers still see typed properties. Depth barely moves;
/// this is a consistency / locality win for the storage ritual only.
@propertyWrapper
struct Pref<Value> {
    let key: String
    let notification: Notification.Name?
    private let read: (UserDefaults, String) -> Value
    private let write: (UserDefaults, String, Value) -> Void

    @available(*, unavailable, message: "@Pref only works as a PreferencesStore stored property")
    var wrappedValue: Value {
        get { fatalError("wrappedValue is unavailable; use the enclosing-instance subscript") }
        set { fatalError("wrappedValue is unavailable; use the enclosing-instance subscript") }
    }

    static subscript(
        _enclosingInstance instance: PreferencesStore,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<PreferencesStore, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<PreferencesStore, Self>
    ) -> Value {
        get {
            let pref = instance[keyPath: storageKeyPath]
            return pref.read(UserDefaults.standard, pref.key)
        }
        set {
            let pref = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            pref.write(UserDefaults.standard, pref.key, newValue)
            if let name = pref.notification {
                NotificationCenter.default.post(name: name, object: nil)
            }
        }
    }
}

extension Pref where Value == Bool {
    init(_ key: String, notification: Notification.Name? = nil) {
        self.key = key
        self.notification = notification
        self.read = { $0.bool(forKey: $1) }
        self.write = { $0.set($2, forKey: $1) }
    }
}

extension Pref where Value: RawRepresentable, Value.RawValue == String {
    init(_ key: String, fallback: Value, notification: Notification.Name? = nil) {
        self.key = key
        self.notification = notification
        self.read = { Value(rawValue: $0.string(forKey: $1) ?? "") ?? fallback }
        self.write = { $0.set($2.rawValue, forKey: $1) }
    }
}
