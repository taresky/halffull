#!/bin/bash
#
# run_launchreason_tests.sh
#
# Runs the LaunchReason test suite without requiring Xcode or XCTest.
# Uses the standard Swift interpreter to inline LaunchReason + lightweight
# assertions — same pattern as run_engine_tests.sh.
#
# Usage:
#     ./Scripts/run_launchreason_tests.sh
#
# CI tip: this script exits non-zero on any test failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/LaunchReason.swift"

if [[ ! -f "$SOURCE" ]]; then
    echo "LaunchReason.swift not found at $SOURCE" >&2
    exit 1
fi

TMP="$(mktemp -t fwc-launchreason-tests.XXXXXX.swift)"
trap 'rm -f "$TMP"' EXIT

cat "$SOURCE" > "$TMP"
cat >> "$TMP" <<'TESTS'

// --- standalone test harness ---
var failures = 0
var total = 0
func check(_ name: String, _ actual: Bool, _ expected: Bool) {
    total += 1
    if actual == expected {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name) — got \(actual), expected \(expected)")
    }
}

func openEvent(loginItem: Bool) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass),
        eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
    if loginItem {
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                       forKeyword: AEKeyword(keyAEPropData))
    }
    return event
}

// Apple Event available (authoritative signal)
check("oapp + lgit flag → login launch (uptime/registration irrelevant)",
      LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: true),
                                     systemUptime: 5000, isLoginItemRegistered: false),
      true)
// The exact hole the old heuristic had: manual open < 90 s after boot
// while registered as a login item must still show the window.
check("oapp without flag → manual, even right after boot",
      LaunchReason.isLoginItemLaunch(event: openEvent(loginItem: false),
                                     systemUptime: 30, isLoginItemRegistered: true),
      false)
let quitEvent = NSAppleEventDescriptor(
    eventClass: AEEventClass(kCoreEventClass),
    eventID: AEEventID(kAEQuitApplication),
    targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID))
check("non-oapp event → manual",
      LaunchReason.isLoginItemLaunch(event: quitEvent,
                                     systemUptime: 30, isLoginItemRegistered: true),
      false)

// No event → legacy uptime heuristic
check("no event + early uptime + registered → login (heuristic fallback)",
      LaunchReason.isLoginItemLaunch(event: nil,
                                     systemUptime: 30, isLoginItemRegistered: true),
      true)
check("no event + late uptime → manual",
      LaunchReason.isLoginItemLaunch(event: nil,
                                     systemUptime: 300, isLoginItemRegistered: true),
      false)
check("no event + not registered → manual",
      LaunchReason.isLoginItemLaunch(event: nil,
                                     systemUptime: 30, isLoginItemRegistered: false),
      false)

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swift "$TMP"
