import Cocoa
import ApplicationServices

/// Writes converted text back to the focused element via Accessibility APIs,
/// without touching the pasteboard or simulating keystrokes.
///
/// This is the preferred conversion path — it leaves the user's clipboard alone,
/// doesn't steal focus, doesn't risk a synthetic ⌘V landing somewhere unexpected.
/// We only fall back to clipboard injection when AX writes aren't accepted by
/// the target element (some Electron / Java / web inputs).
enum AXTextEditor {

    enum Result {
        /// Replaced text in place via AX. Nothing else to do.
        case applied
        /// Element supports text but selection/value writes were rejected.
        /// Caller should fall back to clipboard injection.
        case writeRejected
        /// We had a selection that, once converted, was identical — no edit needed.
        case noChange
    }

    /// Try to apply `convert` to whatever text the user has focused (selection if
    /// any, otherwise the full field value). Returns whether the AX path
    /// succeeded, or `writeRejected` so the caller can attempt the clipboard fallback.
    static func applyConversion(
        to target: FocusInspector.TextElement,
        convert: (String) -> String
    ) -> Result {
        // Prefer the selection — it's what the user explicitly highlighted.
        // A non-empty selection plus a writable selectedText is the gold-standard path.
        if let selection = target.selectedText, !selection.isEmpty {
            let converted = convert(selection)
            if converted == selection { return .noChange }
            if target.selectionIsSettable {
                let err = AXUIElementSetAttributeValue(
                    target.element,
                    kAXSelectedTextAttribute as CFString,
                    converted as CFString
                )
                return err == .success ? .applied : .writeRejected
            }
            return .writeRejected
        }

        // No selection — operate on the entire field value.
        if let value = target.value, !value.isEmpty {
            let converted = convert(value)
            if converted == value { return .noChange }
            if target.valueIsSettable {
                let err = AXUIElementSetAttributeValue(
                    target.element,
                    kAXValueAttribute as CFString,
                    converted as CFString
                )
                return err == .success ? .applied : .writeRejected
            }
            return .writeRejected
        }

        // Element is focused but has no text to operate on.
        return .noChange
    }
}
