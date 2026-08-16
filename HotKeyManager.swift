import Cocoa
import Carbon.HIToolbox

/// Carbon-backed global hotkey. One instance per registered hotkey.
///
/// Why Carbon: `NSEvent.addGlobalMonitorForEvents` cannot consume the event, so a hotkey
/// like ⌘⇧F would also fire in the foreground app. Carbon's `RegisterEventHotKey` is
/// the only API on macOS that registers a system-wide hotkey AND swallows it.
final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRefs: [TargetMode: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    /// 'FWCv' — distinguishes our hotkey events from other Carbon hotkeys in-process.
    private static let signature: FourCharCode = {
        let chars: [UInt8] = [0x46, 0x57, 0x43, 0x76]  // F W C v
        return chars.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }()
    private init() {}

    /// Register (or re-register) the global hotkey.
    /// - Parameters:
    ///   - hotKey: the binding to register (virtual key + Carbon modifier bits).
    ///   - handler: invoked on the main thread when the hotkey fires.
    func register(_ hotKey: HotKey, for mode: TargetMode, handler: @escaping () -> Void) {
        unregister(mode)
        handlers[mode.hotKeyID] = handler

        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: mode.hotKeyID)
        let status = RegisterEventHotKey(hotKey.keyCode,
                                         hotKey.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRefs[mode] = ref
        } else {
            handlers[mode.hotKeyID] = nil
            NSLog("halfFull: RegisterEventHotKey failed for \(mode.rawValue) (status=\(status))")
        }
    }

    /// Tear down one target's hotkey. Safe to call repeatedly.
    func unregister(_ mode: TargetMode) {
        if let ref = hotKeyRefs.removeValue(forKey: mode) {
            UnregisterEventHotKey(ref)
        }
        handlers[mode.hotKeyID] = nil
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
            if hotKeyID.signature == HotKeyManager.signature {
                DispatchQueue.main.async { manager.handlers[hotKeyID.id]?() }
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
