import XCTest
import AppKit
@testable import halfFull

final class ClipboardPlainifierTests: XCTestCase {
    func testNonTextPasteboardIsLeftUntouched() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        pasteboard.writeObjects([item])
        let changeCount = pasteboard.changeCount

        XCTAssertEqual(ClipboardPlainifier.plainify(pasteboard, options: .none), .noText)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.types, [.png])
    }

    func testRichTextIsCleanedAndRewrittenAsStringOnly() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("a\tb", forType: .string)
        item.setData(Data("{\\rtf1 a b}".utf8), forType: .rtf)
        pasteboard.writeObjects([item])

        XCTAssertEqual(
            ClipboardPlainifier.plainify(pasteboard, options: .init(replaceTabs: true)),
            .success(itemCount: 1)
        )
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.types, [.string])
        XCTAssertEqual(pasteboard.string(forType: .string), "a b")
    }

    func testMultipleTextItemsKeepTheirBoundaries() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.writeObjects([first, second])

        XCTAssertEqual(ClipboardPlainifier.plainify(pasteboard, options: .none),
                       .success(itemCount: 2))
        XCTAssertEqual((pasteboard.pasteboardItems ?? []).compactMap {
            $0.string(forType: .string)
        }, ["first", "second"])
    }

    func testConcurrentOwnerChangeIsNeverOverwritten() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        let provider = RacingProvider(pasteboard: pasteboard)
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.writeObjects([item])

        XCTAssertEqual(ClipboardPlainifier.plainify(pasteboard, options: .none),
                       .clipboardChanged)
        XCTAssertEqual(pasteboard.string(forType: .string), "new")
        _ = provider // Keep the lazy provider alive through the assertions.
    }
}

private final class RacingProvider: NSObject, NSPasteboardItemDataProvider {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        item.setString("old", forType: type)
        self.pasteboard.clearContents()
        self.pasteboard.setString("new", forType: .string)
    }
}
