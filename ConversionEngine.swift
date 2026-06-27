import Foundation

/// Direction of conversion.
enum ConversionDirection: String, CaseIterable, Identifiable {
    case toFullWidth   // 半角 → 全角
    case toHalfWidth   // 全角 → 半角
    case smart         // sample text and pick

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .toFullWidth: return NSLocalizedString("direction.toFullWidth", value: "Half → Full-width", comment: "")
        case .toHalfWidth: return NSLocalizedString("direction.toHalfWidth", value: "Full → Half-width", comment: "")
        case .smart:       return NSLocalizedString("direction.smart",       value: "Smart (auto)", comment: "")
        }
    }
}

/// Which categories of characters are subject to conversion.
enum ConversionScope: String, CaseIterable, Identifiable {
    case all            // letters, digits, punctuation, space
    case punctuation    // punctuation/symbols only
    case alphanumeric   // letters + digits only

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .all:           return NSLocalizedString("scope.all",           value: "Everything", comment: "")
        case .punctuation:   return NSLocalizedString("scope.punctuation",   value: "Punctuation only", comment: "")
        case .alphanumeric:  return NSLocalizedString("scope.alphanumeric",  value: "Letters & digits only", comment: "")
        }
    }
}

/// Pure, AppKit-free conversion logic. Trivially testable.
struct ConversionEngine {

    // MARK: - Public API

    /// Convert `text` according to the resolved direction.
    /// `direction == .smart` is resolved against the actual content of `text`.
    static func convert(_ text: String,
                        direction: ConversionDirection,
                        scope: ConversionScope = .all,
                        convertSpace: Bool = true) -> String {
        let resolved = (direction == .smart) ? inferDirection(text) : direction
        switch resolved {
        case .toFullWidth: return toFullWidth(text, scope: scope, convertSpace: convertSpace)
        case .toHalfWidth: return toHalfWidth(text, scope: scope, convertSpace: convertSpace)
        case .smart:       return text   // unreachable
        }
    }

    /// Half-width → full-width.
    /// ASCII 0x21–0x7E → 0xFF01–0xFF5E (offset +0xFEE0). Space → U+3000 when `convertSpace`.
    static func toFullWidth(_ text: String,
                            scope: ConversionScope = .all,
                            convertSpace: Bool = true) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0x21 && v <= 0x7E, scope.includes(asciiCode: v) {
                out.append(UnicodeScalar(v + 0xFEE0)!)
            } else if v == 0x20, convertSpace, scope == .all {
                out.append(UnicodeScalar(0x3000)!)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Full-width → half-width.
    /// 0xFF01–0xFF5E → 0x21–0x7E. Ideographic space U+3000 → 0x20 when `convertSpace`.
    static func toHalfWidth(_ text: String,
                            scope: ConversionScope = .all,
                            convertSpace: Bool = true) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E, scope.includes(asciiCode: v - 0xFEE0) {
                out.append(UnicodeScalar(v - 0xFEE0)!)
            } else if v == 0x3000, convertSpace, scope == .all {
                out.append(UnicodeScalar(0x20)!)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// Sample `text` and pick the direction that "fixes" the dominant form.
    ///
    /// Walks the full string (conversion is already O(n), so the savings of a
    /// `prefix(200)` cap aren't worth misclassifying long documents whose first
    /// 200 scalars disagree with the body — e.g. a license header on a full-width
    /// body would otherwise misroute to `.toFullWidth` and silently rewrite the
    /// header against user intent).
    ///
    /// We deliberately do NOT count bare ASCII space / ideographic space toward
    /// the tally — a CJK paragraph that happens to contain a few ASCII spaces
    /// shouldn't flip the heuristic to `.toFullWidth` and silently inject
    /// U+3000 everywhere. Only convertible non-space scalars vote.
    ///
    /// Returns `.toFullWidth` for empty / all-CJK input (preserves v1.0 behavior
    /// where users intentionally invoke this on plain Latin text).
    static func inferDirection(_ text: String) -> ConversionDirection {
        var halfCount = 0
        var fullCount = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0x21 && v <= 0x7E { halfCount += 1 }
            else if v >= 0xFF01 && v <= 0xFF5E { fullCount += 1 }
        }
        return fullCount > halfCount ? .toHalfWidth : .toFullWidth
    }
}

private extension ConversionScope {
    /// Given an ASCII code (0x21–0x7E), decide whether it falls in this scope.
    func includes(asciiCode v: UInt32) -> Bool {
        switch self {
        case .all:
            return true
        case .alphanumeric:
            return (0x30...0x39).contains(v)   // 0–9
                || (0x41...0x5A).contains(v)   // A–Z
                || (0x61...0x7A).contains(v)   // a–z
        case .punctuation:
            // Treat `_` (0x5F) as a word character even though it's not in [A-Za-z0-9].
            // Without this carve-out, "my_var" becomes "my＿var" under "punctuation only",
            // which surprises every programmer.
            if v == 0x5F { return false }
            return !(0x30...0x39).contains(v)
                && !(0x41...0x5A).contains(v)
                && !(0x61...0x7A).contains(v)
        }
    }
}
