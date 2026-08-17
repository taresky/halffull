import XCTest
@testable import halfFull

final class PlainTextCleanerTests: XCTestCase {
    func testNoOptionsPreserveInputExactly() {
        XCTAssertEqual(PlainTextCleaner.clean("  Rich\ttext\r\n", options: .none),
                       "  Rich\ttext\r\n")
    }

    func testPerLineWhitespaceTrimming() {
        let options = PlainTextCleaner.Options(
            trimTrailingLineWhitespace: true,
            trimLeadingLineWhitespace: true
        )
        XCTAssertEqual(PlainTextCleaner.clean(" \ta \t\r\n\tb\t \n", options: options),
                       "a\r\nb\n")
    }

    func testInvisibleRemovalPreservesTabsAndLineBreaks() {
        let options = PlainTextCleaner.Options(removeInvisibleCharacters: true)
        XCTAssertEqual(PlainTextCleaner.clean("a\u{200B}b\u{0007}\t\r\n", options: options),
                       "ab\t\r\n")
    }

    func testInvisibleRemovalNormalizesNonBreakingSpaces() {
        let options = PlainTextCleaner.Options(removeInvisibleCharacters: true)
        XCTAssertEqual(PlainTextCleaner.clean("a\u{00A0}b", options: options), "a b")
        XCTAssertEqual(PlainTextCleaner.clean("a\u{0003}b", options: options), "a b")
    }

    func testHardWrapRemovalDoesNotMergeWordsOrParagraphs() {
        let options = PlainTextCleaner.Options(removeLineBreaks: true)
        XCTAssertEqual(PlainTextCleaner.clean("a\r\nb\n\nc\rd", options: options),
                       "a b\n\nc d")
    }

    func testBlankLineRemoval() {
        let options = PlainTextCleaner.Options(removeBlankLines: true)
        XCTAssertEqual(PlainTextCleaner.clean("a\n \t\nb\r\n\r\nc", options: options),
                       "a\nb\r\nc")
    }

    func testSmartQuotesBecomeStraightQuotes() {
        let options = PlainTextCleaner.Options(straightenQuotes: true)
        XCTAssertEqual(PlainTextCleaner.clean("„a“ ”b” «c» ›d‹ ‚e‘ ’f’", options: options),
                       "\"a\" \"b\" \"c\" 'd' 'e' 'f'")
    }

    func testSpacesAndTabsAreIndependentOptions() {
        XCTAssertEqual(
            PlainTextCleaner.clean("a   b\t\t  c", options: .init(collapseSpaces: true)),
            "a b\t\t c"
        )
        XCTAssertEqual(
            PlainTextCleaner.clean("a\t\tb", options: .init(replaceTabs: true)),
            "a  b"
        )
        XCTAssertEqual(
            PlainTextCleaner.clean(
                "a \tb",
                options: .init(collapseSpaces: true, replaceTabs: true)
            ),
            "a b"
        )
    }

    func testLossyASCIIConversion() {
        XCTAssertEqual(
            PlainTextCleaner.clean("café", options: .init(convertToASCII: true)),
            "cafe"
        )
    }

    func testLossyASCIIConversionKeepsLegacyTransliterations() {
        XCTAssertEqual(
            PlainTextCleaner.clean(
                "ÄÖÜäöüßæœ–—•·",
                options: .init(convertToASCII: true)
            ),
            "AeOeUeaeoeuessaeoe--**"
        )
    }

    func testASCIIConversionPreservesUnsupportedScriptsInsteadOfQuestionMarks() {
        XCTAssertEqual(
            PlainTextCleaner.clean(
                "Ubuntu LTS（长期支持版） café 🙂",
                options: .init(convertToASCII: true)
            ),
            "Ubuntu LTS（长期支持版） cafe 🙂"
        )
    }

    func testAllCleanupOptionsPreserveMultilingualText() {
        let options = PlainTextCleaner.Options(
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

        XCTAssertEqual(
            PlainTextCleaner.clean("  Ubuntu LTS （长期支持版）\t“café”  \n", options: options),
            "Ubuntu LTS （长期支持版） \"cafe\""
        )
    }

    func testUnicodeNormalizationRunsBeforeASCIIConversion() {
        XCTAssertEqual(
            PlainTextCleaner.clean(
                "A\u{0308}",
                options: .init(convertToASCII: true, normalizeUnicode: true)
            ),
            "Ae"
        )
    }

    func testUnicodeNormalizationEmitsNFC() {
        let normalized = PlainTextCleaner.clean(
            "e\u{0301}",
            options: .init(normalizeUnicode: true)
        )
        XCTAssertEqual(normalized.unicodeScalars.map(\.value), [0x00E9])
    }

    func testWholeStringTrim() {
        XCTAssertEqual(
            PlainTextCleaner.clean(" \t\nhello\r\n ", options: .init(trimWholeString: true)),
            "hello"
        )
    }
}
