import Cocoa

/// Captures and restores the system pasteboard around a conversion so the user's
/// existing clipboard content survives the copy/paste roundtrip we use to inject text.
enum PasteboardArbiter {

    /// A snapshot of every (type, data) pair currently on a pasteboard item.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    /// Capture every item and every representation. We snapshot at the Data level
    /// (not just .string) so non-text pasteboard contents (images, files, RTF) round-trip.
    static func snapshot(_ pasteboard: NSPasteboard = .general) -> Snapshot {
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return Snapshot(items: saved)
    }

    /// Restore a previously captured snapshot. Clears the pasteboard first.
    static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let items = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
