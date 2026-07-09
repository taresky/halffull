import Cocoa

/// Imperative shell for a conversion request.
///
/// Builds the pure transform, checks trust, asks `EditableField` to rewrite,
/// then runs the `ConversionPolicy` plan (notifications / success sound /
/// permission prompt). Routing rules live in the policy; this type only wires
/// effects.
final class ConversionController {

    static let shared = ConversionController()
    private init() {}

    /// Trigger a conversion using the user's preferences for direction/scope.
    func trigger() {
        trigger(directionOverride: nil, scopeOverride: nil)
    }

    /// Trigger with explicit overrides (used by per-mode menu items).
    func trigger(directionOverride: ConversionDirection?, scopeOverride: ConversionScope?) {
        let prefs = PreferencesStore.shared
        let direction = directionOverride ?? prefs.conversionDirection
        let scope = scopeOverride ?? prefs.conversionScope

        // Build the closure once so both edit paths convert with identical settings.
        let convert: (String) -> String = { text in
            ConversionEngine.convert(
                text,
                direction: direction,
                scope: scope,
                convertSpace: prefs.convertSpaceToIdeographic
            )
        }

        // ── Gate: no Accessibility → plan is requireTrust; never touch the field ──
        guard AccessibilityHelper.shared.isTrusted else {
            execute(ConversionPolicy.plan(.untrusted))
            return
        }

        let outcome = EditableField.apply(
            convert,
            options: EditableField.Options(restoreClipboard: prefs.restoreClipboard)
        )
        execute(ConversionPolicy.plan(.edited(Self.fieldResult(outcome))))
    }

    // MARK: - Shell: perform the plan

    private func execute(_ plan: ConversionPolicy.Plan) {
        switch plan {
        case .requireTrust:
            AccessibilityHelper.shared.ensureTrustedPrompt()
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.permissionTitle",
                                         value: "Accessibility permission required", comment: ""),
                body: NSLocalizedString("notify.permissionBody",
                                        value: "Grant access in System Settings → Privacy & Security → Accessibility.", comment: ""))

        case .applied:
            playSuccessSoundIfEnabled()

        case .noChange:
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.noChangeTitle",
                                         value: "Nothing changed", comment: ""),
                body: NSLocalizedString("notify.noChangeBody",
                                        value: "Text already matches the target form.", comment: ""))

        case .notFocused:
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.noFocusTitle",
                                         value: "No text field in focus", comment: ""),
                body: NSLocalizedString("notify.noFocusBody",
                                        value: "Click into a text field, then try again.", comment: ""))

        case .unreadable:
            NotificationPresenter.shared.notify(
                title: NSLocalizedString("notify.nothingTitle",
                                         value: "Nothing to convert", comment: ""),
                body: NSLocalizedString("notify.nothingBody",
                                        value: "Couldn't read the focused field. Try selecting the text manually.", comment: ""))

        case .silent:
            return
        }
    }

    private static func fieldResult(_ outcome: EditableField.Outcome) -> ConversionPolicy.FieldResult {
        switch outcome {
        case .applied:    return .applied
        case .noChange:   return .noChange
        case .notFocused: return .notFocused
        case .unreadable: return .unreadable
        case .busy:       return .busy
        }
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
