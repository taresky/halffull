/// Pure routing for a conversion attempt.
///
/// Maps plain values (trust + what happened to the focused field) to a `Plan`
/// the imperative shell executes. No AppKit, no singletons — the interface is
/// the test surface. Hotkey and menu items share one policy through the shell.
enum ConversionPolicy {

    /// What the shell should do. Data, not effects.
    enum Plan: Equatable {
        /// Accessibility not granted — prompt System Settings and notify.
        case requireTrust
        /// Text was rewritten. Play success sound if the user enabled it.
        case applied
        /// Focused text already matched the transform.
        case noChange
        /// Nothing editable is focused.
        case notFocused
        /// Focused but no text could be read (fallback copy failed).
        case unreadable
        /// Refuse silently (e.g. clipboard restore still pending).
        case silent
    }

    /// Field-level result, mirrored from `EditableField.Outcome` so this module
    /// stays free of AppKit and unit-testable with plain `swift`.
    enum FieldResult: Equatable {
        case applied
        case noChange
        case notFocused
        case unreadable
        case busy
    }

    /// A conversion attempt's pure inputs: either trust was missing, or the
    /// field was edited and reported a result.
    enum Attempt: Equatable {
        case untrusted
        case edited(FieldResult)
    }

    /// Decide the plan. Every branch is pure and unit-tested.
    static func plan(_ attempt: Attempt) -> Plan {
        switch attempt {
        case .untrusted:
            return .requireTrust
        case .edited(let field):
            switch field {
            case .applied:    return .applied
            case .noChange:   return .noChange
            case .notFocused: return .notFocused
            case .unreadable: return .unreadable
            case .busy:       return .silent
            }
        }
    }
}
