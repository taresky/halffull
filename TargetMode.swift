import Carbon.HIToolbox

/// The user-visible destination an action operates on.
enum TargetMode: String, CaseIterable, Identifiable, Hashable {
    case focusedText
    case clipboard

    var id: String { rawValue }

    var defaultHotKey: HotKey {
        switch self {
        case .focusedText:
            return .defaultBinding
        case .clipboard:
            return HotKey(keyCode: UInt32(kVK_ANSI_A),
                          carbonModifiers: UInt32(optionKey))
        }
    }

    /// Stable identifier placed in Carbon's `EventHotKeyID` payload.
    var hotKeyID: UInt32 {
        switch self {
        case .focusedText: return 1
        case .clipboard:   return 2
        }
    }
}
