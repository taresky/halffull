import Cocoa
import ApplicationServices

/// The focused text field, and how halfFull rewrites it.
///
/// **Deep module.** Callers hand in a pure `transform` and get back an `Outcome`.
/// *Which* mechanism did the work — a direct Accessibility write, or the
/// clipboard-injection fallback for stubborn Electron / Java / web inputs that
/// refuse AX writes — is hidden behind the seam. The clipboard snapshot/restore,
/// `changeCount` verification, synthetic ⌘A/⌘C/⌘V, and restore timing all live
/// in here, not in the caller. The old `.writeRejected` result that leaked the
/// AX-vs-clipboard choice back to `ConversionController` is gone.
enum EditableField {

    /// What happened to the focused field. The caller maps these to a
    /// notification / success sound — it never learns which path ran.
    enum Outcome {
        /// Text was rewritten (via AX or clipboard).
        case applied
        /// Focused text already matched the transform's output; nothing written.
        case noChange
        /// Focus isn't a text-editing element we can safely touch.
        case notFocused
        /// Focused, but no text could be read to convert (the fallback copy
        /// produced nothing — focus loss, or the app rejected synthetic events).
        case unreadable
        /// A previous conversion's clipboard restore is still pending; this call
        /// was refused so it can't race that restore. Caller should stay silent.
        case busy
    }

    /// Caller-controlled tunables (sourced from preferences).
    struct Options {
        /// Restore the user's clipboard after the fallback paste settles.
        var restoreClipboard: Bool
    }

    /// True while a clipboard fallback's deferred restore is still pending.
    ///
    /// The re-entrancy guard lives here — right next to the pasteboard it
    /// protects — rather than in the caller: a second hotkey press must not
    /// snapshot/overwrite a clipboard that's about to be restored to the user's
    /// original contents. AX-only conversions never set this, so back-to-back
    /// presses on a well-behaved field are never throttled.
    private static var restorePending = false

    /// Apply `transform` to whatever text the user has focused.
    ///
    /// Prefers a direct AX write; falls back to clipboard injection only when the
    /// element refuses AX writes. Returns synchronously with the outcome — any
    /// clipboard restore is scheduled internally. Assumes the caller already
    /// holds Accessibility trust (it owns the distinct permission prompt).
    static func apply(_ transform: (String) -> String, options: Options) -> Outcome {
        guard !restorePending else { return .busy }

        guard let target = FocusInspector.currentTextElement() else {
            return .notFocused
        }

        switch applyViaAccessibility(to: target, transform: transform) {
        case .applied:       return .applied
        case .noChange:      return .noChange
        case .writeRejected: break   // fall through to the clipboard fallback
        }

        return applyViaClipboard(transform: transform, options: options)
    }

    // MARK: - AX direct edit (preferred path)

    private enum AXResult { case applied, writeRejected, noChange }

    /// Read the selection (or the full value), convert it, write it back via AX.
    /// Clipboard untouched, focus untouched, no synthetic keystrokes.
    private static func applyViaAccessibility(
        to target: FocusInspector.TextElement,
        transform: (String) -> String
    ) -> AXResult {
        // Prefer the selection — it's what the user explicitly highlighted.
        // A non-empty selection plus a writable selectedText is the gold-standard path.
        if let selection = target.selectedText, !selection.isEmpty {
            let converted = transform(selection)
            if converted == selection { return .noChange }
            guard target.selectionIsSettable else { return .writeRejected }
            let err = AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextAttribute as CFString,
                converted as CFString
            )
            return err == .success ? .applied : .writeRejected
        }

        // No selection — operate on the entire field value.
        if let value = target.value, !value.isEmpty {
            let converted = transform(value)
            if converted == value { return .noChange }
            guard target.valueIsSettable else { return .writeRejected }
            let err = AXUIElementSetAttributeValue(
                target.element,
                kAXValueAttribute as CFString,
                converted as CFString
            )
            return err == .success ? .applied : .writeRejected
        }

        // Element is focused but has no text to operate on.
        return .noChange
    }

    // MARK: - Clipboard fallback (legacy synthetic-keystroke path)

    /// Only reached when AX writes are rejected. Selects-all, copies, converts,
    /// pastes, then restores the user's clipboard once the paste has settled.
    private static func applyViaClipboard(
        transform: (String) -> String,
        options: Options
    ) -> Outcome {
        let pasteboard = NSPasteboard.general
        let snapshot = options.restoreClipboard ? PasteboardArbiter.snapshot(pasteboard) : nil

        // Snapshot changeCount so we can verify ⌘C actually copied something. If it
        // didn't (focus loss since the focus check, slow main runloop, or the app
        // rejecting synthetic events), bail out instead of operating on the user's
        // pre-existing clipboard contents.
        let preCopyChangeCount = pasteboard.changeCount

        KeyboardSimulator.press(.a, modifiers: .maskCommand)
        usleep(20_000)
        KeyboardSimulator.press(.c, modifiers: .maskCommand)
        usleep(60_000)

        guard pasteboard.changeCount != preCopyChangeCount,
              let copied = pasteboard.string(forType: .string),
              !copied.isEmpty else {
            scheduleRestore(snapshot, afterDelay: 0)
            return .unreadable
        }

        let converted = transform(copied)
        guard converted != copied else {
            scheduleRestore(snapshot, afterDelay: 0)
            return .noChange
        }

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        usleep(20_000)
        KeyboardSimulator.press(.v, modifiers: .maskCommand)

        // 250ms is enough for the synthetic ⌘V to settle in the target app before
        // we overwrite the pasteboard with the user's original content.
        scheduleRestore(snapshot, afterDelay: 0.25)
        return .applied
    }

    /// Restore the clipboard (if captured) after `delay`, clearing the
    /// re-entrancy guard only once the restore lands — so a second press can't
    /// race the still-pending restore.
    private static func scheduleRestore(_ snapshot: PasteboardArbiter.Snapshot?,
                                        afterDelay delay: TimeInterval) {
        restorePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let snapshot {
                PasteboardArbiter.restore(snapshot, to: NSPasteboard.general)
            }
            restorePending = false
        }
    }
}
