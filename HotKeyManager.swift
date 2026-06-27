import Cocoa
import Carbon.HIToolbox

/// Carbon-backed global hotkey. One instance per registered hotkey.
///
/// Why Carbon: `NSEvent.addGlobalMonitorForEvents` cannot consume the event, so a hotkey
/// like ⌘⇧F would also fire in the foreground app. Carbon's `RegisterEventHotKey` is
/// the only API on macOS that registers a system-wide hotkey AND swallows it.
final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var fired: (() -> Void)?

    /// 'FWCv' — distinguishes our hotkey events from other Carbon hotkeys in-process.
    private static let signature: FourCharCode = {
        let chars: [UInt8] = [0x46, 0x57, 0x43, 0x76]  // F W C v
        return chars.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }()
    private static let id: UInt32 = 1

    private init() {}

    /// Register (or re-register) the global hotkey.
    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - carbonModifiers: combination of `cmdKey | shiftKey | optionKey | controlKey`.
    ///   - handler: invoked on the main thread when the hotkey fires.
    func register(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        self.fired = handler

        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        let status = RegisterEventHotKey(keyCode,
                                         carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            self.hotKeyRef = ref
        } else {
            NSLog("halfFull: RegisterEventHotKey failed (status=\(status))")
        }
    }

    /// Tear down the hotkey. Safe to call repeatedly.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        fired = nil
    }

    // MARK: - Private

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(eventRef,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            guard err == noErr else { return err }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyID.signature == HotKeyManager.signature && hotKeyID.id == HotKeyManager.id {
                DispatchQueue.main.async { manager.fired?() }
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &eventSpec,
                                         selfPtr,
                                         &handlerRef)
        if status != noErr {
            // Without the handler, RegisterEventHotKey can still report noErr — the user
            // would see "the hotkey just does nothing." Log it so we have a breadcrumb.
            NSLog("halfFull: InstallEventHandler failed (status=\(status)) — hotkey will not fire")
            return
        }
        self.eventHandler = handlerRef
    }
}

// MARK: - Modifier flag translation

/// Translate between Carbon modifier bits (used by RegisterEventHotKey) and
/// AppKit's `NSEvent.ModifierFlags` (used by the recorder UI).
enum ModifierTranslator {

    static func carbonFlags(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var flags: UInt32 = 0
        if cocoa.contains(.command) { flags |= UInt32(cmdKey) }
        if cocoa.contains(.shift)   { flags |= UInt32(shiftKey) }
        if cocoa.contains(.option)  { flags |= UInt32(optionKey) }
        if cocoa.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    static func cocoaFlags(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    static func symbolicDescription(carbonModifiers: UInt32, keyCode: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(KeyCode.label(forVirtualKey: keyCode))
        return parts.joined()
    }
}
