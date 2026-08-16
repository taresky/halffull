#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d -t halffull-clipboard-plainifier-tests)"
TMP="$TMP_DIR/main.swift"
BIN="$TMP_DIR/tests"
trap 'rm -rf "$TMP_DIR"' EXIT

cat "$ROOT/PlainTextCleaner.swift" > "$TMP"
if [[ -f "$ROOT/ClipboardPlainifier.swift" ]]; then
    cat "$ROOT/ClipboardPlainifier.swift" >> "$TMP"
fi

cat >> "$TMP" <<'TESTS'

import AppKit

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

let nonTextBoard = NSPasteboard.withUniqueName()
nonTextBoard.clearContents()
let imageItem = NSPasteboardItem()
imageItem.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
nonTextBoard.writeObjects([imageItem])
let nonTextCount = nonTextBoard.changeCount

check("non-text pasteboard is left untouched",
      ClipboardPlainifier.plainify(nonTextBoard, options: .none) == .noText
      && nonTextBoard.changeCount == nonTextCount
      && nonTextBoard.pasteboardItems?.first?.types == [.png])

let richBoard = NSPasteboard.withUniqueName()
richBoard.clearContents()
let richItem = NSPasteboardItem()
richItem.setString("a\tb", forType: .string)
richItem.setData(Data("{\\rtf1 a b}".utf8), forType: .rtf)
richBoard.writeObjects([richItem])

check("text is cleaned and rewritten as string only",
      ClipboardPlainifier.plainify(
        richBoard,
        options: .init(replaceTabs: true)
      ) == .success(itemCount: 1)
      && richBoard.pasteboardItems?.first?.types == [.string]
      && richBoard.pasteboardItems?.first?.string(forType: .string) == "a b")

let multiBoard = NSPasteboard.withUniqueName()
multiBoard.clearContents()
let firstItem = NSPasteboardItem()
firstItem.setString("first", forType: .string)
let secondItem = NSPasteboardItem()
secondItem.setString("second", forType: .string)
multiBoard.writeObjects([firstItem, secondItem])

let multiResult = ClipboardPlainifier.plainify(multiBoard, options: .none)
let multiStrings = (multiBoard.pasteboardItems ?? []).compactMap {
    $0.string(forType: .string)
}
check("multiple text items keep their boundaries",
      multiResult == .success(itemCount: 2)
      && multiStrings == ["first", "second"])

final class RacingProvider: NSObject, NSPasteboardItemDataProvider {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString("old", forType: type)
        self.pasteboard.clearContents()
        self.pasteboard.setString("new", forType: .string)
    }
}

let racingBoard = NSPasteboard.withUniqueName()
racingBoard.clearContents()
let racingItem = NSPasteboardItem()
let racingProvider = RacingProvider(pasteboard: racingBoard)
racingItem.setDataProvider(racingProvider, forTypes: [.string])
racingBoard.writeObjects([racingItem])

check("a concurrent clipboard owner change is never overwritten",
      ClipboardPlainifier.plainify(racingBoard, options: .none) == .clipboardChanged
      && racingBoard.string(forType: .string) == "new")

print("\n\(total - failures)/\(total) passed")
exit(failures == 0 ? 0 : 1)
TESTS

swiftc -framework AppKit "$TMP" -o "$BIN"
"$BIN"
