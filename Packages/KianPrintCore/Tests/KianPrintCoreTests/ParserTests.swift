import XCTest
@testable import KianPrintCore

final class ParserTests: XCTestCase {
    func testEnglishFrontMatterAndDirectives() throws {
        let source = """
        ---
        font-size: 13pt
        top: 30mm
        page-number: off
        ---
        # 訴状
        @tab(12)left
        架空県架空市一丁目@end
        @page
        本文
        """
        let document = try KianParser().parse(source)
        XCTAssertEqual(document.settings.fontSize, 13)
        XCTAssertEqual(document.settings.topMargin, 30 * KianSettings.pointsPerMillimeter, accuracy: 0.001)
        XCTAssertFalse(document.settings.showsPageNumbers)
        XCTAssertNil(document.settings.preset)
        XCTAssertTrue(document.blocks.contains { if case .tabbed = $0 { return true }; return false })
        XCTAssertTrue(document.blocks.contains { if case .pageBreak = $0 { return true }; return false })
    }

    func testNoFrontMatterUsesCourtPreset() throws {
        let document = try KianParser().parse("架空の本文")
        XCTAssertEqual(document.settings.preset, .court)
        XCTAssertTrue(document.settings.usesStandardCourtGrid)
    }

    func testEmptyFrontMatterAlsoUsesCourtPreset() throws {
        let document = try KianParser().parse("---\n\n---\n架空の本文")
        XCTAssertEqual(document.settings.preset, .court)
        XCTAssertTrue(document.settings.usesStandardCourtGrid)
    }

    func testCourtPresetOverridesEveryOtherSettingRegardlessOfOrder() throws {
        let source = """
        ---
        font-size: 99pt
        top: この値も無視される
        page-number: off
        preset: court
        spacing: 1pt
        ---
        架空の本文
        """
        let document = try KianParser().parse(source)

        XCTAssertEqual(document.settings.preset, .court)
        XCTAssertEqual(document.settings.fontSize, 12)
        XCTAssertEqual(document.settings.topMargin, 35 * KianSettings.pointsPerMillimeter, accuracy: 0.001)
        XCTAssertEqual(document.settings.lineSpacing, 13.62, accuracy: 0.001)
        XCTAssertTrue(document.settings.showsPageNumbers)
        XCTAssertTrue(document.settings.usesStandardCourtGrid)
    }

    func testManualCourtValuesDoNotActivateCourtPreset() throws {
        let source = """
        ---
        paper: A4
        font: Hiragino Mincho ProN W3
        font-size: 12pt
        top: 35mm
        bottom: 27mm
        left: 30mm
        right: 22mm
        kern: 0pt
        spacing: 13.62pt
        page-number: on
        kinsoku: court
        ---
        架空の本文
        """
        let document = try KianParser().parse(source)
        XCTAssertNil(document.settings.preset)
        XCTAssertFalse(document.settings.usesStandardCourtGrid)
        XCTAssertEqual(document.settings.fontName, "Hiragino Mincho ProN W3")
        XCTAssertEqual(document.settings.kinsokuMode, "court")
    }

    func testCustomCharacterAndLineSpacingLeaveCourtGrid() throws {
        let source = """
        ---
        font-size: 12pt
        kern: 0.2pt
        spacing: 6pt
        ---
        架空の本文
        """
        let document = try KianParser().parse(source)

        XCTAssertEqual(document.settings.characterSpacing, 0.2, accuracy: 0.001)
        XCTAssertEqual(document.settings.lineSpacing, 6, accuracy: 0.001)
        XCTAssertEqual(document.settings.lineAdvance, 18, accuracy: 0.001)
        XCTAssertFalse(document.settings.usesStandardCourtGrid)
    }

    func testInvalidSettingReportsLineNumber() {
        XCTAssertThrowsError(try KianParser().parse("---\ntop: 大きめ\n---\n本文")) { error in
            XCTAssertEqual((error as? KianIssue)?.line, 2)
        }
    }

    func testNewTablePreservesSpacesAndChangesAlignment() throws {
        let source = """
        @table(4,8,3)center\tleft\tright
        　甲１　\t　　　　　**契約書**\t原本
        left\tcenter\tright
        甲２\t*納品書*\t写し@end
        """
        let document = try KianParser().parse(source)
        guard case .table(let table) = document.blocks[0] else { return XCTFail("table not parsed") }
        XCTAssertEqual(table.columnWidthsInFontUnits, [4, 8, 3])
        XCTAssertEqual(table.headerAlignments, [.center, .leading, .trailing])
        XCTAssertEqual(table.headers[0].plainText, "　甲１　")
        XCTAssertEqual(table.headers[1].plainText, "　　　　　契約書")
        XCTAssertTrue(table.headers[1].inlines.contains(where: \.bold))
        XCTAssertEqual(table.rows[0].alignments, [.leading, .center, .trailing])
        XCTAssertTrue(table.rows[0].cells[1].inlines.contains(where: \.italic))
    }

    func testAlignmentCountIsNormalizedAndPureTableDisablesHeaderRepeat() throws {
        let document = try KianParser().parse("""
        @table(1,2,3;puretable)right
        一\t二
        center\tleft\tright\tcenter
        あ\tい\tう@end
        """)
        guard case .table(let table) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(table.headerAlignments, [.trailing, .leading, .leading])
        XCTAssertEqual(table.rows[0].alignments, [.center, .leading, .trailing])
        XCTAssertEqual(table.headers.map(\.plainText), ["一", "二", ""])
        XCTAssertFalse(table.repeatsHeader)
    }

    func testMoreContentCellsThanWidthsIsRejected() {
        XCTAssertThrowsError(try KianParser().parse("""
        @table(1,2)left\tleft
        一\t二\t三@end
        """))
    }

    func testOldKianPrint2AndRemovedJapaneseDirectivesAreRejected() {
        XCTAssertThrowsError(try KianParser().parse("""
        @table(1,2) {
        | 一 | 二 |
        | --- | --- |
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @tab(1,2) {
        一\t二
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        | 一 | 二 |
        | --- | --- |
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @証拠説明書(列幅=4,8,3,6,6,10) {
        | 符号番号 | 標目 |  | 作成年月日 | 作成者 | 立証趣旨 |
        | --- | --- | --- | --- | --- | --- |
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @事件情報 {
        事件名: 架空事件
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @罫線なし表(列幅=3,20,6) {
        | １ | 訴状副本 | １通 |
        | --- | --- | --- |
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("@改ページ"))
        XCTAssertThrowsError(try KianParser().parse("""
        @右揃え {
        本文
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @中央揃え {
        本文
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @右配置 {
        本文
        }
        """))
    }

    func testTabColumnsAcceptAnyCountPreserveFieldsAndAlignment() throws {
        let document = try KianParser().parse("""
        @tab(1,2,3,4,5,6,7,8,9,10,11,12)left\tcenter\tright
        \t原　告\t株式会社架空商事
        right
        \t上記代表者代表取締役\t架　空　花　子@end
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.columnWidthsInFontUnits, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(block.lines[0].cells.count, 12)
        XCTAssertEqual(block.lines[0].alignments.prefix(3), [.leading, .center, .trailing])
        XCTAssertEqual(block.lines[1].alignments.prefix(3), [.trailing, .leading, .leading])
    }

    func testTabbedFieldsPreserveIntentionalFullwidthSpaces() throws {
        let document = try KianParser().parse("""
        @tab(1,7)left\tright
        　訴訟物の価額\t１００万円@end
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.lines[0].cells[0].map(\.text).joined(), "　訴訟物の価額")
    }

    func testEndMustBeAttachedToFinalDataLine() {
        XCTAssertThrowsError(try KianParser().parse("""
        @tab(6,6)left\tright
        項目\t値
        @end
        """))
    }

    func testLineEndAlignmentAndAbsoluteSizeModifiers() throws {
        let document = try KianParser().parse("""
        附属書類@center@size(24)
        弁護士　架　空　太　郎　殿@size(20)
        以上@right(36)
        """)
        guard case .paragraph(let centered) = document.blocks[0],
              case .paragraph(let sized) = document.blocks[1],
              case .paragraph(let right) = document.blocks[2] else { return XCTFail() }
        XCTAssertEqual(centered.plainText, "附属書類")
        XCTAssertEqual(centered.alignment, .center)
        XCTAssertEqual(centered.fontSize, 24)
        XCTAssertEqual(sized.alignment, .leading)
        XCTAssertEqual(sized.fontSize, 20)
        XCTAssertEqual(right.alignment, .trailing)
        XCTAssertEqual(right.trailingInset, 36)
    }

    func testMarkdownHeadingAndQuoteMarkersArePlainText() throws {
        let document = try KianParser().parse("# 見出し\n> 引用")
        guard case .paragraph(let heading) = document.blocks[0],
              case .paragraph(let quote) = document.blocks[1] else { return XCTFail() }
        XCTAssertEqual(heading.plainText, "# 見出し")
        XCTAssertEqual(quote.plainText, "> 引用")
    }

    func testAlignmentWordsDoNotStartTabbedLayoutWithoutTabDirective() throws {
        let document = try KianParser().parse("left\tcenter\tright")
        guard case .paragraph(let paragraph) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(paragraph.plainText, "left\tcenter\tright")
    }
}
