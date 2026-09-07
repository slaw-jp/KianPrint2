import XCTest
@testable import KianPrintCore

final class TypographyTests: XCTestCase {
    private let settings = KianSettings()

    func testLineStartProhibition() {
        let text = KianTypography.attributedString(from: [KianInline(text: "これは架空の文章です、次の文章です。")], settings: settings)
        let lines = KianLineBreaker().breakLines(text, width: 70)
        for line in lines.dropFirst() {
            XCTAssertFalse(KianLineBreaker.prohibitedAtLineStart.contains(String(line.attributedText.string.prefix(1))))
        }
    }

    func testLineEndProhibition() {
        let text = KianTypography.attributedString(from: [KianInline(text: "架空の文章（括弧の中身）です。")], settings: settings)
        let lines = KianLineBreaker().breakLines(text, width: 64)
        for line in lines.dropLast() {
            XCTAssertFalse(KianLineBreaker.prohibitedAtLineEnd.contains(String(line.attributedText.string.suffix(1))))
        }
    }

    func testDoesNotSplitGraphemeCluster() {
        let source = "あいう👨‍👩‍👧‍👦えお"
        let text = KianTypography.attributedString(from: [KianInline(text: source)], settings: settings)
        let lines = KianLineBreaker().breakLines(text, width: 25)
        XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
    }

    func testAvoidsBreakingLatinWordWhenPossible() {
        let text = KianTypography.attributedString(from: [KianInline(text: "日本語 KianPrint2 application 文書")], settings: settings)
        let lines = KianLineBreaker().breakLines(text, width: 100)
        XCTAssertFalse(lines.contains { $0.attributedText.string == "KianPri" })
    }

    func testDeterministicPaginationAndExplicitBreak() throws {
        let document = try KianParser().parse("第一頁\n@改ページ\n第二頁")
        let first = KianLayoutEngine().layout(document)
        let second = KianLayoutEngine().layout(document)
        XCTAssertEqual(first.pages.count, 2)
        XCTAssertEqual(first.pages.map(\.commands.count), second.pages.map(\.commands.count))
    }

    func testHeadingOccupiesOneNormalLineAndPageFits26Lines() throws {
        let body = (1...25).map { "本文\($0)" }.joined(separator: "\n")
        let document = try KianParser().parse("# 見出し\n\(body)")
        let layout = KianLayoutEngine().layout(document)

        XCTAssertEqual(layout.pages.count, 1)
        let textOrigins = layout.pages[0].commands.compactMap { command -> CGPoint? in
            guard case .text(let text) = command else { return nil }
            return text.origin
        }
        XCTAssertEqual(textOrigins.count, 26)
        XCTAssertEqual(textOrigins[1].y - textOrigins[0].y, document.settings.lineAdvance, accuracy: 0.001)
    }

    func testStandardCourtGridFitsExactly37FullwidthCharacters() throws {
        let document = try KianParser().parse(String(repeating: "あ", count: 74))
        let layout = KianLayoutEngine().layout(document)
        let lines = layout.pages[0].commands.compactMap { command -> String? in
            guard case .text(let text) = command else { return nil }
            return text.text.string
        }

        XCTAssertTrue(document.settings.usesStandardCourtGrid)
        XCTAssertEqual(lines.map(\.count), [37, 37])
    }

    func testCourtFrameUsesLegacySlackForHalfwidthText() throws {
        let firstLine = String(repeating: "あ", count: 34)
        let secondLine = String(repeating: "い", count: 32)
        let source = "第１　架空の項目\n　　\(firstLine)\(secondLine)II.A)価格"
        let document = try KianParser().parse(source)
        let layout = KianLayoutEngine().layout(document)
        let lines = layout.pages[0].commands.compactMap { command -> String? in
            guard case .text(let text) = command else { return nil }
            return text.text.string
        }

        XCTAssertEqual(lines[1], "　　\(firstLine)")
        XCTAssertEqual(lines[2], "\(secondLine)II.A)価")
        XCTAssertEqual(lines[3], "格")
    }

    func testHangingIndentUsesWiderFirstLineLikeLegacyKianPrint() throws {
        let prefix = String(repeating: "あ", count: 30)
        let source = "第１　総論\n１　架空の事情\n　　\(prefix)令和２年１月"
        let document = try KianParser().parse(source)
        let layout = KianLayoutEngine().layout(document)
        let lines = layout.pages[0].commands.compactMap { command -> String? in
            guard case .text(let text) = command else { return nil }
            return text.text.string
        }

        XCTAssertEqual(lines[2].count, 36)
        XCTAssertTrue(lines[2].hasSuffix("令和２年"))
        XCTAssertTrue(lines[3].hasPrefix("１月"))
    }

    func testPageNumberIsCenteredInBottomMargin() throws {
        let document = try KianParser().parse("第一頁\n@改ページ\n第二頁")
        let layout = KianLayoutEngine().layout(document)
        guard case .text(let pageNumber) = layout.pages[0].commands.last else {
            return XCTFail("ページ番号がありません。")
        }

        let textCenterY = pageNumber.origin.y + (pageNumber.ascent + pageNumber.descent) / 2
        let bottomMarginCenterY = document.settings.paperHeight - document.settings.bottomMargin / 2
        XCTAssertEqual(pageNumber.text.string, "1")
        XCTAssertEqual(textCenterY, bottomMarginCenterY, accuracy: 0.001)
    }
}
