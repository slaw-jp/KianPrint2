import CoreText
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

    func testMatchingManualValuesDoNotGiveHeadingCourtLineAdvance() throws {
        let body = (1...25).map { "本文\($0)" }.joined(separator: "\n")
        let source = """
        ---
        文字サイズ: 12pt
        上余白: 35mm
        下余白: 27mm
        左余白: 30mm
        右余白: 22mm
        字間: 0pt
        行間: 13.62pt
        禁則処理: 裁判所
        ---
        # 見出し
        \(body)
        """
        let document = try KianParser().parse(source)
        let layout = KianLayoutEngine().layout(document)

        XCTAssertFalse(document.settings.usesStandardCourtGrid)
        XCTAssertEqual(layout.pages.count, 2)
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

    func testHeadingSizesUseTheExactLegacyRatios() throws {
        let document = try KianParser().parse("""
        ---
        文字サイズ: 15pt
        ---
        # 大見出し
        ## 中見出し
        ### 小見出し
        #### 本文見出し
        """)
        let layout = KianLayoutEngine().layout(document)
        let sizes = layout.pages[0].commands.compactMap { command -> CGFloat? in
            guard case .text(let placed) = command,
                  placed.text.length > 0,
                  let fontAttribute = placed.text.attribute(
                    kCTFontAttributeName as NSAttributedString.Key,
                    at: 0,
                    effectiveRange: nil
                  ) else { return nil }
            let font = fontAttribute as! CTFont
            return CTFontGetSize(font)
        }
        XCTAssertEqual(sizes, [22.5, 20, 17.5, 15])
    }

    func testNumericRightInsetKeepsThreeTwelvePointCharactersClear() throws {
        let document = try KianParser().parse("""
        @右揃え(3) {
        原告訴訟代理人弁護士　架　空　太　郎
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        guard case .text(let signature) = layout.pages[0].commands[0] else { return XCTFail() }
        let expectedRight = document.settings.paperWidth
            - document.settings.rightMargin
            - 36
        XCTAssertEqual(signature.origin.x + signature.width, expectedRight, accuracy: 0.001)
    }

    func testSpecifiedColumnWidthsAreAbsoluteAndTableStaysLeftAligned() throws {
        let document = try KianParser().parse("""
        @表(列幅=4,8,3,6,6,10; 先頭行=中央) {
        | 符号番号 | 標目 |  | 作成年月日 | 作成者 | 立証趣旨 |
        | --- | --- | --- | --- | --- | --- |
        | 甲１ | 契約書 | 原本 | 令和８年 | 原告 | 契約の成立 |
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let top = document.settings.topMargin
        let verticalXs = layout.pages[0].commands.compactMap { command -> CGFloat? in
            guard case .line(let from, let to, _) = command,
                  abs(from.x - to.x) < 0.001,
                  abs(from.y - top) < 0.001 else { return nil }
            return from.x
        }
        XCTAssertEqual(verticalXs.count, 7)
        let widths: [CGFloat] = [4, 8, 3, 6, 6, 10]
        for index in widths.indices {
            XCTAssertEqual(
                verticalXs[index + 1] - verticalXs[index],
                widths[index] * 12,
                accuracy: 0.001
            )
        }
        XCTAssertLessThan(verticalXs.last!, document.settings.leftMargin + document.settings.contentWidth)
    }

    func testFirstRowCanBeCenteredWhileBodyUsesColumnAlignment() throws {
        let document = try KianParser().parse("""
        @表(列幅=8,12; 先頭行=中央) {
        | 標目 | 作成者 |
        | --- | --- |
        | 契約書 | 原告及び被告 |
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let texts = layout.pages[0].commands.compactMap { command -> KianPlacedText? in
            guard case .text(let placed) = command else { return nil }
            return placed
        }
        let header = try XCTUnwrap(texts.first { $0.text.string == "標目" })
        let body = try XCTUnwrap(texts.first { $0.text.string == "契約書" })
        XCTAssertGreaterThan(header.origin.x, document.settings.leftMargin)
        XCTAssertEqual(body.origin.x, document.settings.leftMargin + 3, accuracy: 0.001)
    }

    func testTabIntervalsAreRelativeAndPlacePartyListFields() throws {
        let document = try KianParser().parse("""
        @タブ(10,11) {
        \t原　告\t株式会社架空商事
        \t上記代表者代表取締役\t架　空　花　子
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let texts = layout.pages[0].commands.compactMap { command -> KianPlacedText? in
            guard case .text(let placed) = command else { return nil }
            return placed
        }
        let role = try XCTUnwrap(texts.first { $0.text.string == "原　告" })
        let company = try XCTUnwrap(texts.first { $0.text.string == "株式会社架空商事" })
        let representativeRole = try XCTUnwrap(texts.first { $0.text.string == "上記代表者代表取締役" })
        let representativeName = try XCTUnwrap(texts.first { $0.text.string == "架　空　花　子" })
        XCTAssertEqual(role.origin.x, document.settings.leftMargin + 10 * 12, accuracy: 0.001)
        XCTAssertEqual(company.origin.x, document.settings.leftMargin + 21 * 12, accuracy: 0.001)
        XCTAssertEqual(representativeRole.origin.x, role.origin.x, accuracy: 0.001)
        XCTAssertEqual(representativeName.origin.x, company.origin.x, accuracy: 0.001)
    }

    func testEachTabUsesItsCorrespondingStopEvenWhenTheFieldWraps() throws {
        let document = try KianParser().parse("""
        @タブ(1,7) {
        　訴訟物の価額\t１００万円
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let texts = layout.pages[0].commands.compactMap { command -> KianPlacedText? in
            guard case .text(let placed) = command else { return nil }
            return placed
        }
        let value = try XCTUnwrap(texts.first { $0.text.string == "１００万円" })
        let labelLines = texts.filter { $0.text.string != "１００万円" && $0.text.string != "" }
        XCTAssertEqual(labelLines.map { $0.text.string }.joined(), "　訴訟物の価額")
        XCTAssertTrue(labelLines.allSatisfy { abs($0.origin.x - document.settings.leftMargin) < 0.001 })
        XCTAssertEqual(value.origin.x, document.settings.leftMargin + 12, accuracy: 0.001)
    }

    func testTabCellDoesNotLeaveOneCharacterAloneOnLastLine() throws {
        let document = try KianParser().parse("""
        @タブ(10,11) {
        \t上記代表者代表取締役社長\t架　空　花　子
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let texts = layout.pages[0].commands.compactMap { command -> KianPlacedText? in
            guard case .text(let placed) = command else { return nil }
            return placed
        }
        let firstLine = try XCTUnwrap(texts.first { $0.text.string == "上記代表者代表取締役" })
        let secondLine = try XCTUnwrap(texts.first { $0.text.string == "社長" })
        let name = try XCTUnwrap(texts.first { $0.text.string == "架　空　花　子" })
        let expectedRoleX = document.settings.leftMargin + 10 * 12
        XCTAssertEqual(firstLine.origin.x, expectedRoleX, accuracy: 0.001)
        XCTAssertEqual(secondLine.origin.x, expectedRoleX, accuracy: 0.001)
        XCTAssertEqual(name.origin.x, document.settings.leftMargin + 21 * 12, accuracy: 0.001)
        XCTAssertEqual(secondLine.origin.y - firstLine.origin.y, document.settings.lineAdvance, accuracy: 0.001)
    }

    func testTabIntervalsCanDefineMoreThanTwoStops() throws {
        let document = try KianParser().parse("""
        @タブ(2,3,4,5) {
        一\t二\t三\t四\t五
        }
        """)
        let layout = KianLayoutEngine().layout(document)
        let origins = layout.pages[0].commands.compactMap { command -> CGFloat? in
            guard case .text(let placed) = command else { return nil }
            return placed.origin.x
        }
        XCTAssertEqual(origins.count, 5)
        let expectedOffsets: [CGFloat] = [0, 24, 60, 108, 168]
        for (origin, expectedOffset) in zip(origins, expectedOffsets) {
            XCTAssertEqual(origin - document.settings.leftMargin, expectedOffset, accuracy: 0.001)
        }
    }
}
