import Cocoa
import Combine
import Carbon.HIToolbox

/// Centralized, observable preferences backed by `UserDefaults`.
/// SwiftUI binds to it via `@ObservedObject`; AppKit reads via the typed properties.
///
/// Adding a new preference is two lines: a key, and a `published(_:default:)` declaration.
final class PreferencesStore: ObservableObject {

    static let shared = PreferencesStore()

    /// Posted (in addition to `objectWillChange`) when the hotkey binding changes,
    /// so `HotKeyManager` can re-register without subscribing to Combine.
    static let hotKeyChangedNotification = Notification.Name("FWCHotKeyChanged")

    // MARK: - Keys (single source of truth — never literal-stringify outside this enum)

    private enum Key {
        static let hotKeyKeyCode = "hotKey.keyCode"
        static let hotKeyCarbonModifiers = "hotKey.carbonModifiers"
        static let conversionDirection = "conversion.direction"
        static let conversionScope = "conversion.scope"
        static let restoreClipboard = "behavior.restoreClipboard"
        static let convertSpaceToIdeographic = "behavior.convertSpaceToIdeographic"
        static let playSoundOnSuccess = "behavior.playSoundOnSuccess"
        static let showNotifications = "behavior.showNotifications"
        static let launchAtLogin = "behavior.launchAtLogin"
        static let hasCompletedOnboarding = "onboarding.completed"
        static let hasGrantedAXBefore = "ax.hasGrantedBefore"
    }

    private let defaults = UserDefaults.standard

    private init() {
        // Defaults are registered (not set) so the user's explicit values win.
        defaults.register(defaults: [
            Key.hotKeyKeyCode: UInt32(kVK_ANSI_F),
            Key.hotKeyCarbonModifiers: UInt32(optionKey),
            Key.conversionDirection: ConversionDirection.smart.rawValue,
            Key.conversionScope: ConversionScope.all.rawValue,
            Key.restoreClipboard: true,
            Key.convertSpaceToIdeographic: true,
            Key.playSoundOnSuccess: false,
            Key.showNotifications: true,
            Key.launchAtLogin: false,
            Key.hasCompletedOnboarding: false,
            Key.hasGrantedAXBefore: false,
        ])
    }

    // MARK: - Hotkey

    var hotKeyKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyKeyCode)) }
        // Setting the keyCode alone is rare (the recorder and the reset button both want to
        // change keyCode AND modifiers together — see `setHotKey(keyCode:carbonModifiers:)`).
        // We keep the single-axis setter for API symmetry but it still re-registers the hotkey.
        set { setHotKey(keyCode: newValue, carbonModifiers: hotKeyCarbonModifiers) }
    }

    var hotKeyCarbonModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyCarbonModifiers)) }
        set { setHotKey(keyCode: hotKeyKeyCode, carbonModifiers: newValue) }
    }

    /// Atomic two-axis setter — writes both keys, fires `objectWillChange` and
    /// `hotKeyChangedNotification` exactly once. Use this instead of mutating the
    /// individual properties back-to-back; otherwise the global hotkey is briefly
    /// re-registered with the new keyCode but the OLD modifiers, which can collide
    /// with another shortcut or be rejected silently by RegisterEventHotKey.
    func setHotKey(keyCode: UInt32, carbonModifiers: UInt32) {
        objectWillChange.send()
        defaults.set(Int(keyCode),         forKey: Key.hotKeyKeyCode)
        defaults.set(Int(carbonModifiers), forKey: Key.hotKeyCarbonModifiers)
        NotificationCenter.default.post(name: Self.hotKeyChangedNotification, object: nil)
    }

    // MARK: - Conversion
    //
    // Setters fire `objectWillChange` BEFORE writing to `defaults`, matching the
    // ObservableObject contract (mirrors @Published's willSet semantics — observers
    // that snap the old value via `objectWillChange.sink { ... }` see the pre-change
    // state, not the post-change one).

    var conversionDirection: ConversionDirection {
        get { ConversionDirection(rawValue: defaults.string(forKey: Key.conversionDirection) ?? "") ?? .smart }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Key.conversionDirection) }
    }

    var conversionScope: ConversionScope {
        get { ConversionScope(rawValue: defaults.string(forKey: Key.conversionScope) ?? "") ?? .all }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Key.conversionScope) }
    }

    // MARK: - Behavior toggles

    var restoreClipboard: Bool {
        get { defaults.bool(forKey: Key.restoreClipboard) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.restoreClipboard) }
    }

    var convertSpaceToIdeographic: Bool {
        get { defaults.bool(forKey: Key.convertSpaceToIdeographic) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.convertSpaceToIdeographic) }
    }

    var playSoundOnSuccess: Bool {
        get { defaults.bool(forKey: Key.playSoundOnSuccess) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.playSoundOnSuccess) }
    }

    var showNotifications: Bool {
        get { defaults.bool(forKey: Key.showNotifications) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.showNotifications) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Sticky bit: flipped to `true` the first time we observe a successful
    /// `AXIsProcessTrusted == true`. Never cleared. Used to distinguish
    /// "fresh install, user hasn't granted yet" from "granted before, but TCC
    /// lost the grant after an ad-hoc-signed update." The latter case triggers
    /// the in-app recovery flow.
    var hasGrantedAXBefore: Bool {
        get { defaults.bool(forKey: Key.hasGrantedAXBefore) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.hasGrantedAXBefore) }
    }
}
