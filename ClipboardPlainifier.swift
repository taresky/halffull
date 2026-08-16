import AppKit

/// Replaces textual pasteboard items with `.string`-only representations.
enum ClipboardPlainifier {
    enum Result: Equatable {
        case success(itemCount: Int)
        case noText
        case clipboardChanged
        case writeFailed
    }

    static func plainify(
        _ pasteboard: NSPasteboard = .general,
        options: PlainTextCleaner.Options
    ) -> Result {
        let observedChangeCount = pasteboard.changeCount
        var originalTextItems: [NSPasteboardItem] = []
        let outputItems = (pasteboard.pasteboardItems ?? []).compactMap { item -> NSPasteboardItem? in
            guard let text = item.string(forType: .string) else { return nil }
            let original = NSPasteboardItem()
            original.setString(text, forType: .string)
            originalTextItems.append(original)

            let output = NSPasteboardItem()
            output.setString(PlainTextCleaner.clean(text, options: options), forType: .string)
            return output
        }
        guard pasteboard.changeCount == observedChangeCount else { return .clipboardChanged }
        guard !outputItems.isEmpty else { return .noText }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(outputItems) else {
            // NSPasteboard has no transactional replace API. If the cleaned
            // write is rejected after clearing, make a best-effort recovery of
            // the original strings so a transient failure does not leave an
            // empty clipboard. Rich representations cannot be restored safely
            // without eagerly materializing potentially huge/private payloads.
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(originalTextItems)
            return .writeFailed
        }
        return .success(itemCount: outputItems.count)
    }
}
