#!/bin/bash
#
# run_engine_tests.sh
#
# Runs the ConversionEngine test suite without requiring Xcode or XCTest.
# Uses the standard Swift interpreter to inline the engine + lightweight assertions.
#
# Usage:
#     ./Scripts/run_engine_tests.sh
#
# CI tip: this script exits non-zero on any test failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/ConversionEngine.swift"

if [[ ! -f "$ENGINE" ]]; then
    echo "ConversionEngine.swift not found at $ENGINE" >&2
    exit 1
fi

TMP="$(mktemp -t fwc-engine-tests.XXXXXX.swift)"
trap 'rm -f "$TMP"' EXIT

cat "$ENGINE" > "$TMP"
cat >> "$TMP" <<'TESTS'

// --- standalone test harness (NSLocalizedString is no-op outside a bundle) ---
var failures = 0
var total = 0
func check(_ name: String, _ actual: String, _ expected: String) {
    total += 1
    if actual == expected {
        print("✓ \(name)")
    } else {
        failures += 1
        let fmt: (String) -> String = { s in
            s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        }
        print("✗ \(name)")
        print("    expected: \(fmt(expected))")
        print("    actual:   \(fmt(actual))")
    }
}
func checkDir(_ name: String, _ actual: ConversionDirection, _ expected: ConversionDirection) {
    total += 1
    if actual == expected {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name) — got \(actual), expected \(expected)")
    }
}

check("ASCII → FW", ConversionEngine.toFullWidth("Hello123"), "Ｈｅｌｌｏ１２３")
check("Punctuation → FW", ConversionEngine.toFullWidth("!@#$%^&*()"), "！＠＃＄％＾＆＊（）")
check("Space → ideographic", ConversionEngine.toFullWidth("A B"), "Ａ\u{3000}Ｂ")
check("Space preserved when disabled", ConversionEngine.toFullWidth("A B", convertSpace: false), "Ａ Ｂ")
check("CJK passes through", ConversionEngine.toFullWidth("中文 Hello"), "中文\u{3000}Ｈｅｌｌｏ")
check("Emoji preserved", ConversionEngine.toFullWidth("A🍎B"), "Ａ🍎Ｂ")
check("Empty FW", ConversionEngine.toFullWidth(""), "")
check("Empty HW", ConversionEngine.toHalfWidth(""), "")
check("FW letters → HW", ConversionEngine.toHalfWidth("Ｈｅｌｌｏ１２３"), "Hello123")
check("Ideographic space → HW", ConversionEngine.toHalfWidth("Ａ\u{3000}Ｂ"), "A B")
check("Ideographic space preserved when disabled", ConversionEngine.toHalfWidth("Ａ\u{3000}Ｂ", convertSpace: false), "A\u{3000}B")
let onceFW = ConversionEngine.toFullWidth("Hello, world! 123")
check("FW idempotent", ConversionEngine.toFullWidth(onceFW), onceFW)
let onceHW = ConversionEngine.toHalfWidth("Ｈｅｌｌｏ，ｗｏｒｌｄ！１２３")
check("HW idempotent", ConversionEngine.toHalfWidth(onceHW), onceHW)
check("FW ∘ HW = identity",
      ConversionEngine.toHalfWidth(ConversionEngine.toFullWidth("Hello, world! 123")),
      "Hello, world! 123")
check("scope.alphanumeric skips punctuation",
      ConversionEngine.toFullWidth("a!b", scope: .alphanumeric), "ａ!ｂ")
check("scope.punctuation skips letters",
      ConversionEngine.toFullWidth("a!b", scope: .punctuation), "a！b")
check("scope.alphanumeric leaves space",
      ConversionEngine.toFullWidth("a b", scope: .alphanumeric), "ａ ｂ")
check("scope.punctuation leaves _ alone (identifier)",
      ConversionEngine.toFullWidth("my_var", scope: .punctuation), "my_var")
checkDir("infer HW → toFW", ConversionEngine.inferDirection("Hello world"), .toFullWidth)
checkDir("infer FW → toHW", ConversionEngine.inferDirection("Ｈｅｌｌｏ\u{3000}ｗｏｒｌｄ"), .toHalfWidth)
checkDir("infer mixed majority", ConversionEngine.inferDirection("Ａｂｃｄｅｆｇabcde"), .toHalfWidth)
checkDir("infer empty → toFW", ConversionEngine.inferDirection(""), .toFullWidth)
checkDir("infer ignores bare ASCII space",
         ConversionEngine.inferDirection("日本語 テスト"), .toFullWidth)
checkDir("infer scans beyond first 200 scalars",
         ConversionEngine.inferDirection(String(repeating: "a", count: 200) + String(repeating: "ａ", count: 1000)),
         .toHalfWidth)
check("toHW scope.alphanumeric leaves FW punctuation alone",
      ConversionEngine.toHalfWidth("ａ！ｂ", scope: .alphanumeric), "a！b")
check("toHW scope.punctuation leaves FW letters alone",
      ConversionEngine.toHalfWidth("ａ！ｂ", scope: .punctuation), "ａ!ｂ")
check("toHW scope.alphanumeric leaves ideographic space alone",
      ConversionEngine.toHalfWidth("ａ\u{3000}ｂ", scope: .alphanumeric), "a\u{3000}b")
check("smart on HW", ConversionEngine.convert("Hello", direction: .smart), "Ｈｅｌｌｏ")
check("smart on FW", ConversionEngine.convert("Ｈｅｌｌｏ", direction: .smart), "Hello")
check("explicit toFW honored",
      ConversionEngine.convert("Ｈｅｌｌｏ abc", direction: .toFullWidth), "Ｈｅｌｌｏ\u{3000}ａｂｃ")
check("combining marks pass through", ConversionEngine.toFullWidth("e\u{0301}"), "ｅ\u{0301}")
check("tilde & backtick (edges)", ConversionEngine.toFullWidth("~`"), "～｀")
check("control chars untouched", ConversionEngine.toFullWidth("\n\t"), "\n\t")

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swift "$TMP"
