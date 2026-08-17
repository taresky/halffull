#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -t halffull-plain-text-cleaner-tests.XXXXXX.swift)"
trap 'rm -f "$TMP"' EXIT

if [[ -f "$ROOT/PlainTextCleaner.swift" ]]; then
    cat "$ROOT/PlainTextCleaner.swift" > "$TMP"
fi

cat >> "$TMP" <<'TESTS'

var failures = 0
var total = 0

func check(_ name: String, _ actual: String, _ expected: String) {
    total += 1
    if actual == expected {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name)")
        print("    expected: \(expected.debugDescription)")
        print("    actual:   \(actual.debugDescription)")
    }
}

func checkCondition(_ name: String, _ condition: @autoclosure () -> Bool) {
    total += 1
    if condition() {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name)")
    }
}

check("no cleaning options preserve text",
      PlainTextCleaner.clean("  Rich\ttext\r\n", options: .none),
      "  Rich\ttext\r\n")

check("trailing line trim preserves line endings",
      PlainTextCleaner.clean(" a \t\r\nb\t \n",
                             options: .init(trimTrailingLineWhitespace: true)),
      " a\r\nb\n")

check("leading line trim preserves line endings",
      PlainTextCleaner.clean(" \ta\r\n\tb\n  c",
                             options: .init(trimLeadingLineWhitespace: true)),
      "a\r\nb\nc")

check("invisible removal preserves tab and line breaks",
      PlainTextCleaner.clean("a\u{200B}b\u{0007}\t\r\n",
                             options: .init(removeInvisibleCharacters: true)),
      "ab\t\r\n")

check("invisible removal normalizes non-breaking spaces",
      PlainTextCleaner.clean("a\u{00A0}b",
                             options: .init(removeInvisibleCharacters: true)),
      "a b")

check("invisible removal turns ETX into spacing",
      PlainTextCleaner.clean("a\u{0003}b",
                             options: .init(removeInvisibleCharacters: true)),
      "a b")

check("hard-wrap removal handles CRLF, CR, and LF without merging words",
      PlainTextCleaner.clean("a\r\nb\rc\nd",
                             options: .init(removeLineBreaks: true)),
      "a b c d")

check("hard-wrap removal preserves paragraph breaks",
      PlainTextCleaner.clean("a\nb\n\nc\nd",
                             options: .init(removeLineBreaks: true)),
      "a b\n\nc d")

check("blank-line removal keeps nonblank line endings",
      PlainTextCleaner.clean("a\n \t\nb\r\n\r\nc",
                             options: .init(removeBlankLines: true)),
      "a\nb\r\nc")

check("smart quotes become straight quotes",
      PlainTextCleaner.clean("„a“ ”b” «c» ›d‹ ‚e‘ ’f’",
                             options: .init(straightenQuotes: true)),
      "\"a\" \"b\" \"c\" 'd' 'e' 'f'")

check("consecutive spaces collapse without touching tabs",
      PlainTextCleaner.clean("a   b\t  c",
                             options: .init(collapseSpaces: true)),
      "a b\t c")

check("tabs become one space each",
      PlainTextCleaner.clean("a\t\tb",
                             options: .init(replaceTabs: true)),
      "a  b")

check("tab replacement runs before consecutive-space collapse",
      PlainTextCleaner.clean("a \tb",
                             options: .init(collapseSpaces: true, replaceTabs: true)),
      "a b")

check("lossy ASCII conversion transliterates accents",
      PlainTextCleaner.clean("café",
                             options: .init(convertToASCII: true)),
      "cafe")

check("lossy ASCII conversion keeps legacy transliterations",
      PlainTextCleaner.clean("ÄÖÜäöüßæœ–—•·",
                             options: .init(convertToASCII: true)),
      "AeOeUeaeoeuessaeoe--**")

check("ASCII conversion preserves unsupported scripts instead of question marks",
      PlainTextCleaner.clean("Ubuntu LTS（长期支持版） café 🙂",
                             options: .init(convertToASCII: true)),
      "Ubuntu LTS（长期支持版） cafe 🙂")

let allOptions = PlainTextCleaner.Options(
    trimTrailingLineWhitespace: true,
    trimLeadingLineWhitespace: true,
    trimWholeString: true,
    removeInvisibleCharacters: true,
    removeLineBreaks: true,
    removeBlankLines: true,
    collapseSpaces: true,
    replaceTabs: true,
    convertToASCII: true,
    straightenQuotes: true,
    normalizeUnicode: true
)
check("all cleanup options preserve multilingual text",
      PlainTextCleaner.clean("  Ubuntu LTS （长期支持版）\t“café”  \n",
                             options: allOptions),
      "Ubuntu LTS （长期支持版） \"cafe\"")

check("Unicode normalization runs before lossy ASCII conversion",
      PlainTextCleaner.clean("A\u{0308}",
                             options: .init(convertToASCII: true, normalizeUnicode: true)),
      "Ae")

let normalized = PlainTextCleaner.clean("e\u{0301}",
                                        options: .init(normalizeUnicode: true))
checkCondition("Unicode normalization emits one NFC scalar",
               normalized.unicodeScalars.map(\.value) == [0x00E9])

check("whole-string trim removes surrounding whitespace and newlines",
      PlainTextCleaner.clean(" \t\nhello\r\n ",
                             options: .init(trimWholeString: true)),
      "hello")

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swift "$TMP"
