import XCTest
@testable import halfFull

final class ConversionEngineTests: XCTestCase {

    // MARK: - toFullWidth

    func testASCIILettersAndDigitsToFullWidth() {
        XCTAssertEqual(ConversionEngine.toFullWidth("Hello123"),
                       "Ｈｅｌｌｏ１２３")
    }

    func testPunctuationToFullWidth() {
        XCTAssertEqual(ConversionEngine.toFullWidth("!@#$%^&*()"),
                       "！＠＃＄％＾＆＊（）")
    }

    func testSpaceConvertedToIdeographicByDefault() {
        XCTAssertEqual(ConversionEngine.toFullWidth("A B"),
                       "Ａ\u{3000}Ｂ")
    }

    func testSpaceLeftAloneWhenDisabled() {
        XCTAssertEqual(ConversionEngine.toFullWidth("A B", convertSpace: false),
                       "Ａ Ｂ")
    }

    func testCJKPassesThroughUntouched() {
        XCTAssertEqual(ConversionEngine.toFullWidth("中文 Hello"),
                       "中文\u{3000}Ｈｅｌｌｏ")
    }

    func testEmojiAndSurrogatesPreserved() {
        // 🍎 is a single non-BMP scalar — must not be mangled.
        XCTAssertEqual(ConversionEngine.toFullWidth("A🍎B"),
                       "Ａ🍎Ｂ")
    }

    func testEmptyStringRoundTrips() {
        XCTAssertEqual(ConversionEngine.toFullWidth(""), "")
        XCTAssertEqual(ConversionEngine.toHalfWidth(""), "")
    }

    // MARK: - toHalfWidth

    func testFullWidthLettersToHalf() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("Ｈｅｌｌｏ１２３"),
                       "Hello123")
    }

    func testIdeographicSpaceToHalf() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("Ａ\u{3000}Ｂ"),
                       "A B")
    }

    func testIdeographicSpaceLeftAloneWhenDisabled() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("Ａ\u{3000}Ｂ", convertSpace: false),
                       "A\u{3000}B")
    }

    // MARK: - Idempotency

    func testFullWidthIsIdempotent() {
        let once = ConversionEngine.toFullWidth("Hello, world! 123")
        let twice = ConversionEngine.toFullWidth(once)
        XCTAssertEqual(once, twice)
    }

    func testHalfWidthIsIdempotent() {
        let once = ConversionEngine.toHalfWidth("Ｈｅｌｌｏ，ｗｏｒｌｄ！１２３")
        let twice = ConversionEngine.toHalfWidth(once)
        XCTAssertEqual(once, twice)
    }

    func testFullWidthIsInverseOfHalfWidth() {
        let source = "Hello, world! 123"
        let roundTrip = ConversionEngine.toHalfWidth(ConversionEngine.toFullWidth(source))
        XCTAssertEqual(roundTrip, source)
    }

    // MARK: - Scope

    func testScopeAlphanumericLeavesPunctuationAlone() {
        XCTAssertEqual(ConversionEngine.toFullWidth("a!b", scope: .alphanumeric),
                       "ａ!ｂ")
    }

    func testScopePunctuationLeavesLettersAlone() {
        XCTAssertEqual(ConversionEngine.toFullWidth("a!b", scope: .punctuation),
                       "a！b")
    }

    func testScopeAlphanumericIgnoresSpace() {
        // Space is only converted when scope is `.all`.
        XCTAssertEqual(ConversionEngine.toFullWidth("a b", scope: .alphanumeric),
                       "ａ ｂ")
    }

    func testScopePunctuationLeavesUnderscoreAlone() {
        // `_` is a word character in every programming context — under .punctuation
        // it must NOT be converted. "my_var" → "my_var", not "my＿var".
        XCTAssertEqual(ConversionEngine.toFullWidth("my_var", scope: .punctuation),
                       "my_var")
    }

    // MARK: - Smart direction inference

    func testInferDirectionPrefersFullWidthWhenInputIsHalfWidth() {
        XCTAssertEqual(ConversionEngine.inferDirection("Hello world"), .toFullWidth)
    }

    func testInferDirectionPrefersHalfWidthWhenInputIsFullWidth() {
        XCTAssertEqual(ConversionEngine.inferDirection("Ｈｅｌｌｏ\u{3000}ｗｏｒｌｄ"),
                       .toHalfWidth)
    }

    func testInferDirectionWithMixedFavorsMajority() {
        // 7 FW letters vs 5 HW letters — should pick toHalfWidth.
        XCTAssertEqual(ConversionEngine.inferDirection("Ａｂｃｄｅｆｇabcde"), .toHalfWidth)
    }

    func testInferDirectionEmptyInputPicksFullWidth() {
        // Ties go to toFullWidth — historical default.
        XCTAssertEqual(ConversionEngine.inferDirection(""), .toFullWidth)
    }

    func testInferDirectionIgnoresAsciiSpaceAlone() {
        // CJK paragraph with stray ASCII spaces shouldn't flip to toFullWidth on
        // the strength of the spaces — only convertible letters/digits/punctuation vote.
        // Tie (0=0) → toFullWidth (the convertSpace flag then handles the actual space).
        XCTAssertEqual(ConversionEngine.inferDirection("日本語 テスト"), .toFullWidth)
    }

    func testInferDirectionScansBeyondFirst200Scalars() {
        // First 250 scalars are ASCII letters; the next 100 are full-width letters.
        // Old `prefix(200)` cap would have classified this as half-width-majority
        // and routed to toFullWidth, silently rewriting the ASCII prefix.
        // The whole-string scan should see 250 half vs 100 full → still toFullWidth here,
        // but the inverse case (next test) is the one that previously broke.
        let head = String(repeating: "a", count: 250)
        let tail = String(repeating: "ａ", count: 100)
        XCTAssertEqual(ConversionEngine.inferDirection(head + tail), .toFullWidth)
    }

    func testInferDirectionScansBeyondFirst200ScalarsRespectsBody() {
        // First 200 scalars are ASCII (header/license); the body is full-width.
        // With the v1.0 sampling cap this returned .toFullWidth and shredded the header.
        // Now: 200 half vs 1000 full → toHalfWidth.
        let header = String(repeating: "a", count: 200)
        let body   = String(repeating: "ａ", count: 1000)
        XCTAssertEqual(ConversionEngine.inferDirection(header + body), .toHalfWidth)
    }

    // MARK: - Scope tests for toHalfWidth (symmetric path)

    func testToHalfWidthScopeAlphanumericLeavesPunctuationAlone() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("ａ！ｂ", scope: .alphanumeric),
                       "a！b")
    }

    func testToHalfWidthScopePunctuationLeavesLettersAlone() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("ａ！ｂ", scope: .punctuation),
                       "ａ!ｂ")
    }

    func testToHalfWidthScopeAlphanumericLeavesIdeographicSpaceAlone() {
        XCTAssertEqual(ConversionEngine.toHalfWidth("ａ\u{3000}ｂ", scope: .alphanumeric),
                       "a\u{3000}b")
    }

    // MARK: - convert(_:direction:scope:) entry point

    func testConvertSmartConvertsToFullWidthOnHalfWidthInput() {
        XCTAssertEqual(ConversionEngine.convert("Hello", direction: .smart),
                       "Ｈｅｌｌｏ")
    }

    func testConvertSmartConvertsToHalfWidthOnFullWidthInput() {
        XCTAssertEqual(ConversionEngine.convert("Ｈｅｌｌｏ", direction: .smart),
                       "Hello")
    }

    func testConvertExplicitlyHonorsRequestedDirection() {
        // Force toFullWidth even though majority is FW — no-op for the FW chars,
        // touches nothing else.
        XCTAssertEqual(ConversionEngine.convert("Ｈｅｌｌｏ abc", direction: .toFullWidth),
                       "Ｈｅｌｌｏ\u{3000}ａｂｃ")
    }

    // MARK: - Unicode edge cases

    func testCombiningMarksPassThrough() {
        // "é" composed as e + U+0301 — the combining mark must not be ascii-mapped.
        let source = "e\u{0301}"
        XCTAssertEqual(ConversionEngine.toFullWidth(source), "ｅ\u{0301}")
    }

    func testTildeAndBacktickConverted() {
        // 0x7E (~) and 0x60 (`) are at the edges of the convertible range.
        XCTAssertEqual(ConversionEngine.toFullWidth("~`"), "～｀")
    }

    func testControlCharactersUntouched() {
        XCTAssertEqual(ConversionEngine.toFullWidth("\n\t"), "\n\t")
    }
}
