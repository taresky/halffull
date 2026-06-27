import Cocoa

/// Coordinates a single conversion request. The dispatch is layered:
///
///   1. Scope guard — query the AX system for what the user has focused.
///      If it's NOT a text-editing element (Finder, desktop, web canvas, …),
///      abort with a notification. **This is the fix for the v2.0 problem
///      where the hotkey would synthesize ⌘A in Finder and wreck things.**
///
///   2. AX direct edit — preferred path. Read selected text (or full value) via
///      Accessibility, run it through the engine, write the result back via AX.
///      Clipboard untouched, focus untouched, no synthetic keystrokes.
///
///   3. Clipboard fallback — only if (2) reports `writeRejected` (some Electron /
///      Java / web inputs refuse AX writes). Uses the legacy synthetic ⌘A/⌘C/⌘V
///      flow with `changeCount` verification.
final class ConversionController {

    static let shared = ConversionController()
    private init() {}

    /// True while a conversion is in-flight. Prevents the user from re-entrantly
    /// hammering the hotkey and racing two copy/paste sequences against each other.
    private var inFlight = false

    /// Trigger a conversion using the user's preferences for direction/scope.
    func trigger() {
        trigger(directionOverride: nil, scopeOverride: nil)
    }

    /// Trigger with explicit overrides (used by per-mode menu items).
    func trigger(directionOverride: ConversionDirection?, scopeOverride: ConversionScope?) {
        guard !inFlight else { return }
        inFlight = true

        let prefs = PreferencesStore.shared
        let direction = directionOverride ?? prefs.conversionDirection
        let scope = scopeOverride ?? prefs.conversionScope

        // Build the closure once so both paths convert with identical settings.
        let convert: (String) -> String = { text in
            ConversionEngine.convert(
                text,
                direction: direction,
                scope: scope,
                convertSpace: prefs.convertSpaceToIdeographic
            )
        }

        // ── 1. Scope guard ──────────────────────────────────────────────────
        guard AccessibilityHelper.shared.isTrusted else {
            AccessibilityHelper.shared.ensureTrustedPrompt()
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.permissionTitle",
                                         value: "Accessibility permission required", comment: ""),
                body: NSLocalizedString("notify.permissionBody",
                                        value: "Grant access in System Settings → Privacy & Security → Accessibility.", comment: ""))
            inFlight = false
            return
        }

        guard let focused = FocusInspector.currentTextElement() else {
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.noFocusTitle",
                                         value: "No text field in focus", comment: ""),
                body: NSLocalizedString("notify.noFocusBody",
                                        value: "Click into a text field, then try again.", comment: ""))
            inFlight = false
            return
        }

        // ── 2. AX direct edit ───────────────────────────────────────────────
        switch AXTextEditor.applyConversion(to: focused, convert: convert) {
        case .applied:
            playSuccessSoundIfEnabled()
            inFlight = false
            return
        case .noChange:
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.noChangeTitle",
                                         value: "Nothing changed", comment: ""),
                body: NSLocalizedString("notify.noChangeBody",
                                        value: "Text already matches the target form.", comment: ""))
            inFlight = false
            return
        case .writeRejected:
            // Fall through to clipboard path.
            break
        }

        // ── 3. Clipboard fallback ───────────────────────────────────────────
        runClipboardFallback(convert: convert, prefs: prefs)
    }

    // MARK: - Clipboard fallback (legacy synthetic-keystroke path)

    private func runClipboardFallback(convert: (String) -> String, prefs: PreferencesStore) {
        let pasteboard = NSPasteboard.general
        let snapshot = prefs.restoreClipboard ? PasteboardArbiter.snapshot(pasteboard) : nil

        // Centralised "we're done" path. Clears inFlight only AFTER the restore lands,
        // so a second hotkey press doesn't race the still-pending clipboard restore.
        func finish(restoring snap: PasteboardArbiter.Snapshot?, afterDelay delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let snap {
                    PasteboardArbiter.restore(snap, to: NSPasteboard.general)
                }
                self.inFlight = false
            }
        }

        // Snapshot changeCount so we can verify Cmd+C actually did something.
        // If it didn't (focus loss between AX check and now, slow main runloop,
        // app rejecting synthetic events), bail out instead of operating on the
        // user's pre-existing clipboard contents.
        let preCopyChangeCount = pasteboard.changeCount

        KeyboardSimulator.press(.a, modifiers: .maskCommand)
        usleep(20_000)
        KeyboardSimulator.press(.c, modifiers: .maskCommand)
        usleep(60_000)

        guard pasteboard.changeCount != preCopyChangeCount,
              let copied = pasteboard.string(forType: .string),
              !copied.isEmpty else {
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.nothingTitle",
                                         value: "Nothing to convert", comment: ""),
                body: NSLocalizedString("notify.nothingBody",
                                        value: "Couldn't read the focused field. Try selecting the text manually.", comment: ""))
            finish(restoring: snapshot, afterDelay: 0)
            return
        }

        let converted = convert(copied)

        guard converted != copied else {
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.noChangeTitle",
                                         value: "Nothing changed", comment: ""),
                body: NSLocalizedString("notify.noChangeBody",
                                        value: "Text already matches the target form.", comment: ""))
            finish(restoring: snapshot, afterDelay: 0)
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        usleep(20_000)
        KeyboardSimulator.press(.v, modifiers: .maskCommand)
        playSuccessSoundIfEnabled()

        // 250ms is enough for the synthetic ⌘V to settle in the target app before
        // we overwrite the pasteboard with the user's original content.
        finish(restoring: snapshot, afterDelay: 0.25)
    }

    private func playSuccessSoundIfEnabled() {
        guard PreferencesStore.shared.playSoundOnSuccess else { return }
        Self.successSound?.play()
    }

    /// Long-lived NSSound reference. Created once and held by the singleton so
    /// the audio engine isn't yanked out from under itself the instant the
    /// `.play()` call returns — the v3.x bug where the user heard nothing despite
    /// the toggle being on was an inline `NSSound(named:)?.play()` whose object
    /// went out of scope before playback even started.
    private static let successSound: NSSound? = {
        let s = NSSound(named: NSSound.Name("Pop"))
        return s
    }()
}
