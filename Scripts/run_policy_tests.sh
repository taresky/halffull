#!/bin/bash
#
# run_policy_tests.sh
#
# Runs the ConversionPolicy test suite without requiring Xcode or XCTest.
# Uses the standard Swift interpreter to inline the policy + lightweight assertions.
#
# Usage:
#     ./Scripts/run_policy_tests.sh
#
# CI tip: this script exits non-zero on any test failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/ConversionPolicy.swift"

if [[ ! -f "$SOURCE" ]]; then
    echo "ConversionPolicy.swift not found at $SOURCE" >&2
    exit 1
fi

TMP="$(mktemp -t fwc-policy-tests.XXXXXX.swift)"
trap 'rm -f "$TMP"' EXIT

cat "$SOURCE" > "$TMP"
cat >> "$TMP" <<'TESTS'

// --- standalone test harness ---
var failures = 0
var total = 0
func check(_ name: String, _ actual: ConversionPolicy.Plan, _ expected: ConversionPolicy.Plan) {
    total += 1
    if actual == expected {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name) — got \(actual), expected \(expected)")
    }
}

check("untrusted → requireTrust",
      ConversionPolicy.plan(.untrusted), .requireTrust)
check("applied → applied",
      ConversionPolicy.plan(.edited(.applied)), .applied)
check("noChange → noChange",
      ConversionPolicy.plan(.edited(.noChange)), .noChange)
check("notFocused → notFocused",
      ConversionPolicy.plan(.edited(.notFocused)), .notFocused)
check("unreadable → unreadable",
      ConversionPolicy.plan(.edited(.unreadable)), .unreadable)
check("busy → silent",
      ConversionPolicy.plan(.edited(.busy)), .silent)

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swift "$TMP"
