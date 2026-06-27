import Cocoa
import ApplicationServices

/// Queries the system-wide accessibility tree for the currently focused UI element
/// and decides whether it's a text-editing context we can safely operate on.
///
/// This is the SCOPE GUARD that prevents the global hotkey from firing ⌘A/⌘C/⌘V
/// while the user is in Finder, on the desktop, or in a non-text element — where
/// our synthetic keystrokes would do destructive nonsense.
enum FocusInspector {

    /// A snapshot of what the user has focus on right now, if it's a text element.
    struct TextElement {
        /// The raw AX element — needed for direct-edit attempts.
        let element: AXUIElement
        /// `kAXValueAttribute` if it's a String.
        let value: String?
        /// `kAXSelectedTextAttribute` — non-nil only when there's a real selection.
        let selectedText: String?
        /// Can we set `kAXValueAttribute` (overwrite the whole field)?
        let valueIsSettable: Bool
        /// Can we set `kAXSelectedTextAttribute` (replace the selection in place)?
        let selectionIsSettable: Bool
    }

    /// Return the focused text element, or nil if focus is on something we shouldn't touch.
    /// Caller must already hold accessibility trust — otherwise this returns nil.
    static func currentTextElement() -> TextElement? {
        guard AccessibilityHelper.shared.isTrusted else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide,
                                                kAXFocusedUIElementAttribute as CFString,
                                                &focused)
        guard err == .success, let focused else { return nil }
        // Safe: AXUIElementCopyAttributeValue returns CFTypeRef; AXUIElement is a CFType.
        let element = focused as! AXUIElement

        guard isTextEditingElement(element) else { return nil }

        return TextElement(
            element: element,
            value: stringAttribute(element, kAXValueAttribute as CFString),
            selectedText: stringAttribute(element, kAXSelectedTextAttribute as CFString),
            valueIsSettable: isAttributeSettable(element, kAXValueAttribute as CFString),
            selectionIsSettable: isAttributeSettable(element, kAXSelectedTextAttribute as CFString)
        )
    }

    // MARK: - Heuristics

    /// True iff the element exposes a text-editing role (or a near-equivalent).
    /// We deliberately keep the allow-list narrow — false-negatives (refusing to act)
    /// are OK; false-positives (acting on the wrong element) are bad.
    private static func isTextEditingElement(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(element, kAXRoleAttribute as CFString) else {
            return false
        }
        switch role {
        case kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole:
            return true
        default:
            // Some apps wrap their editor in a generic AXGroup but still expose the
            // text attributes. Allow it only when both .value (String) and
            // .selectedText are present — that's a strong signal it's editable text.
            let value = stringAttribute(element, kAXValueAttribute as CFString)
            let selectable = (attributeExists(element, kAXSelectedTextAttribute as CFString))
            return value != nil && selectable
        }
    }

    // MARK: - AX helpers

    private static func stringAttribute(_ element: AXUIElement, _ attr: CFString) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &result) == .success,
              let str = result as? String else {
            return nil
        }
        return str
    }

    private static func isAttributeSettable(_ element: AXUIElement, _ attr: CFString) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attr, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func attributeExists(_ element: AXUIElement, _ attr: CFString) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let array = names as? [String] else {
            return false
        }
        return array.contains(attr as String)
    }
}
