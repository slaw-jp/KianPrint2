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
        @tab(12) {
        \t架空県架空市一丁目
        }
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

    func testGenericTableAndInlineMarkup() throws {
        let source = """
        # 証拠説明書
        | 号証 | 標目 | 作成年月日 | 作成者 | 立証趣旨 | 備考 |
        | :---: | --- | :---: | --- | --- | --- |
        | 甲１ | **契約書** 原本 | R8.1.1 | 架空太郎 | *契約成立* | |
        """
        let document = try KianParser().parse(source)
        guard case .table(let table) = document.blocks.first(where: { if case .table = $0 { return true }; return false }) else {
            return XCTFail("table not parsed")
        }
        XCTAssertTrue(table.rows[0].cells[1].inlines.contains(where: \.bold))
        XCTAssertTrue(table.rows[0].cells[4].inlines.contains(where: \.italic))
    }

    func testTableDirectivesAcceptVariableColumnWidths() throws {
        let bordered = try KianParser().parse("""
        @table(1,2,3; center) {
        | 左 | 中 | 右 |
        | --- | :---: | ---: |
        | あ | い | う |
        }
        """)
        guard case .table(let borderedTable) = bordered.blocks[0] else { return XCTFail() }
        XCTAssertEqual(borderedTable.columnWidthsInFontUnits ?? [], [1, 2, 3])
        XCTAssertEqual(borderedTable.firstRowAlignment, .center)

        let rightHeader = try KianParser().parse("""
        @table(1,2,3; right) {
        | 左 | 中 | 右 |
        | --- | --- | --- |
        }
        """)
        guard case .table(let rightHeaderTable) = rightHeader.blocks[0] else { return XCTFail() }
        XCTAssertEqual(rightHeaderTable.firstRowAlignment, .trailing)
    }

    func testColumnWidthCountMustMatchTable() {
        XCTAssertThrowsError(try KianParser().parse("""
        @table(1,2) {
        | 一 | 二 | 三 |
        | --- | --- | --- |
        | あ | い | う |
        }
        """))
    }

    func testRemovedAndJapaneseDirectivesAreRejected() {
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

    func testTabIntervalsAcceptAnyCountAndPreserveTabFields() throws {
        let document = try KianParser().parse("""
        @tab(1,2,3,4,5,6,7,8,9,10,11,12) {
        \t原　告\t株式会社架空商事
        \t上記代表者代表取締役\t架　空　花　子
        }
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.tabIntervalsInFontUnits, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(block.lines[0].cells.count, 3)
        XCTAssertEqual(block.lines[1].cells.count, 3)
    }

    func testTabbedFieldsPreserveIntentionalFullwidthSpaces() throws {
        let document = try KianParser().parse("""
        @tab(1,7) {
        　訴訟物の価額\t１００万円
        }
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.lines[0].cells[0].map(\.text).joined(), "　訴訟物の価額")
    }
}
