#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -t halffull-target-mode-tests.XXXXXX.swift)"
trap 'rm -f "$TMP"' EXIT

cat "$ROOT/KeyCode.swift" "$ROOT/HotKey.swift" > "$TMP"
if [[ -f "$ROOT/TargetMode.swift" ]]; then
    cat "$ROOT/TargetMode.swift" >> "$TMP"
fi

cat >> "$TMP" <<'TESTS'

var failures = 0
var total = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    total += 1
    if condition() {
        print("✓ \(name)")
    } else {
        failures += 1
        print("✗ \(name)")
    }
}

check("two target modes", TargetMode.allCases == [.focusedText, .clipboard])
check("focused text defaults to Option-F",
      TargetMode.focusedText.defaultHotKey == .defaultBinding)
check("clipboard defaults to Option-A",
      TargetMode.clipboard.defaultHotKey.keyCode == UInt32(kVK_ANSI_A)
      && TargetMode.clipboard.defaultHotKey.carbonModifiers == UInt32(optionKey))
check("hotkey ids are distinct",
      TargetMode.focusedText.hotKeyID != TargetMode.clipboard.hotKeyID)

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swift "$TMP"
