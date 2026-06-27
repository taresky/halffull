import Cocoa

/// Posts synthetic keystrokes via CGEvent. Used to drive Cmd+A / Cmd+C / Cmd+V
/// against the currently focused text field of whatever app holds keyboard focus.
enum KeyboardSimulator {

    /// Press-and-release `key` while holding `modifiers`.
    /// Posts events to the HID event tap so they're indistinguishable from physical input.
    static func press(_ key: KeyCode, modifiers: CGEventFlags = []) {
        // A nil event source produces the most "physical" event — many apps that filter on
        // event source treat tap-injected nil-source events as user input.
        let down = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }
}
