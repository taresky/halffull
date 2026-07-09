import Cocoa
import Carbon.HIToolbox

/// A global hotkey binding.
///
/// A hotkey is two correlated values: a virtual key code and Carbon modifier
/// bits. Keep them together so callers cannot accidentally pass a new key with
/// stale modifiers, or format one half without the other.
struct HotKey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let defaultBinding = HotKey(keyCode: UInt32(kVK_ANSI_F),
                                       carbonModifiers: UInt32(optionKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(keyCode: UInt32, cocoaModifiers: NSEvent.ModifierFlags) {
        self.init(keyCode: keyCode,
                  carbonModifiers: Self.carbonFlags(from: cocoaModifiers))
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        Self.cocoaFlags(from: carbonModifiers)
    }

    var symbolicDescription: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(KeyCode.label(forVirtualKey: keyCode))
        return parts.joined()
    }

    private static func carbonFlags(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var flags: UInt32 = 0
        if cocoa.contains(.command) { flags |= UInt32(cmdKey) }
        if cocoa.contains(.shift)   { flags |= UInt32(shiftKey) }
        if cocoa.contains(.option)  { flags |= UInt32(optionKey) }
        if cocoa.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    private static func cocoaFlags(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbon & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}
