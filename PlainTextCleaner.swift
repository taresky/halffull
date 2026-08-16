import Foundation

/// Pure, deterministic text cleanup used by the clipboard target.
enum PlainTextCleaner {
    struct Options: Equatable {
        var trimTrailingLineWhitespace = false
        var trimLeadingLineWhitespace = false
        var trimWholeString = false
        var removeInvisibleCharacters = false
        var removeLineBreaks = false
        var removeBlankLines = false
        var collapseSpaces = false
        var replaceTabs = false
        var convertToASCII = false
        var straightenQuotes = false
        var normalizeUnicode = false

        static let none = Options()
    }

    static func clean(_ text: String, options: Options) -> String {
        var result = text

        if options.trimTrailingLineWhitespace {
            result = result.replacingOccurrences(
                of: #"[ \t]+(?=\r\n|\r|\n|$)"#,
                with: "",
                options: .regularExpression
            )
        }

        if options.trimLeadingLineWhitespace {
            result = result.replacingOccurrences(
                of: #"(?m)^[ \t]+"#,
                with: "",
                options: .regularExpression
            )
        }

        if options.removeInvisibleCharacters {
            for (source, replacement) in Self.legacyInvisibleReplacements {
                result = result.replacingOccurrences(of: source, with: replacement)
            }
            result = result.unicodeScalars.reduce(into: "") { output, scalar in
                if scalar == "\t" || scalar == "\n" || scalar == "\r" {
                    output.unicodeScalars.append(scalar)
                    return
                }
                switch scalar.properties.generalCategory {
                case .control, .format:
                    return
                default:
                    output.unicodeScalars.append(scalar)
                }
            }
        }

        if options.removeLineBreaks {
            result = result.replacingOccurrences(
                of: #"\r\n|\r"#,
                with: "\n",
                options: .regularExpression
            )
            // Plain Clip called this "remove hard wraps": join adjacent
            // nonblank lines with a separating space, while leaving paragraph
            // boundaries (and leading/trailing line breaks) intact.
            result = result.replacingOccurrences(
                of: #"(?<=[^\n])\n(?=[^\n])"#,
                with: " ",
                options: .regularExpression
            )
        }

        if options.normalizeUnicode {
            result = result.precomposedStringWithCanonicalMapping
        }

        if options.replaceTabs {
            result = result.replacingOccurrences(of: "\t", with: " ")
        }

        if options.collapseSpaces {
            result = result.replacingOccurrences(
                of: #" {2,}"#,
                with: " ",
                options: .regularExpression
            )
        }

        if options.removeBlankLines {
            result = result.replacingOccurrences(
                of: #"(?m)^[ \t]*(?:\r\n|\r|\n)"#,
                with: "",
                options: .regularExpression
            )
        }

        if options.straightenQuotes {
            result = result.unicodeScalars.reduce(into: "") { output, scalar in
                switch scalar {
                case "„", "“", "”", "»", "«":
                    output.append("\"")
                case "›", "‹", "‚", "‘", "’":
                    output.append("'")
                default:
                    output.unicodeScalars.append(scalar)
                }
            }
        }

        if options.convertToASCII {
            result = result.unicodeScalars.reduce(into: "") { output, scalar in
                if let replacement = Self.legacyASCIIReplacements[scalar] {
                    output.append(replacement)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
            if let data = result.data(using: .ascii, allowLossyConversion: true),
               let ascii = String(data: data, encoding: .ascii) {
                result = ascii
            }
        }

        if options.trimWholeString {
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    /// Plain Clip's invisible cleanup first normalizes these exceptional
    /// sequences, then the modern implementation also removes remaining
    /// control/format scalars while preserving tabs and line endings.
    private static let legacyInvisibleReplacements: [(String, String)] = [
        ("\0 ", " "), (" \0", " "), ("\0", ""),
        ("\u{00A0} ", " "), (" \u{00A0}", " "), ("\u{00A0}", " "),
        ("\u{0003} ", " "), (" \u{0003}", " "), ("\u{0003}", " "),
        ("\u{00AD}", "")
    ]

    /// Explicit transliterations from Plain Clip 2.5.2, applied before
    /// Foundation's general lossy ASCII conversion.
    private static let legacyASCIIReplacements: [UnicodeScalar: String] = [
        "“": "\"", "”": "\"", "»": "\"", "«": "\"",
        "›": "'", "‹": "'", "‘": "'", "’": "'",
        "–": "-", "—": "-",
        "Ä": "Ae", "Ö": "Oe", "Ü": "Ue",
        "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
        "æ": "ae", "œ": "oe", "•": "*", "·": "*"
    ]
}
