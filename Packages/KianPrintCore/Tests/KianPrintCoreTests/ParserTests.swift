import XCTest
@testable import KianPrintCore

final class ParserTests: XCTestCase {
    func testJapaneseFrontMatterAndDirectives() throws {
        let source = """
        ---
        文字サイズ: 13pt
        上余白: 30mm
        ページ番号: なし
        ---
        # 訴状
        @右配置 {
        架空郵便番号
        架空県架空市一丁目
        }
        @改ページ
        本文
        """
        let document = try KianParser().parse(source)
        XCTAssertEqual(document.settings.fontSize, 13)
        XCTAssertEqual(document.settings.topMargin, 30 * KianSettings.pointsPerMillimeter, accuracy: 0.001)
        XCTAssertFalse(document.settings.showsPageNumbers)
        XCTAssertNil(document.settings.preset)
        XCTAssertTrue(document.blocks.contains { if case .blockBox = $0 { return true }; return false })
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
        文字サイズ: 99pt
        上余白: この値も無視される
        ページ番号: なし
        プリセット: 裁判所
        行間: 1pt
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
        文字サイズ: 12pt
        上余白: 35mm
        下余白: 27mm
        左余白: 30mm
        右余白: 22mm
        字間: 0pt
        行間: 13.62pt
        ページ番号: あり
        禁則処理: 裁判所
        ---
        架空の本文
        """
        let document = try KianParser().parse(source)
        XCTAssertNil(document.settings.preset)
        XCTAssertFalse(document.settings.usesStandardCourtGrid)
    }

    func testCustomCharacterAndLineSpacingLeaveCourtGrid() throws {
        let source = """
        ---
        文字サイズ: 12pt
        字間: 0.2pt
        行間: 6pt
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
        XCTAssertThrowsError(try KianParser().parse("---\n上余白: 大きめ\n---\n本文")) { error in
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

    func testNumericRightInsetUsesTwelvePointCharacterUnits() throws {
        let document = try KianParser().parse("""
        @右配置(3) {
        原告訴訟代理人弁護士　架　空　太　郎
        }
        """)
        guard case .blockBox(let box) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(box.trailingInset, 36, accuracy: 0.001)
    }

    func testFormerRightInsetArgumentsAreRejected() {
        XCTAssertThrowsError(try KianParser().parse("""
        @右配置(印) {
        原告訴訟代理人弁護士　架　空　太　郎
        }
        """))
        XCTAssertThrowsError(try KianParser().parse("""
        @右揃え(30pt) {
        原告訴訟代理人弁護士　架　空　太　郎
        }
        """))
    }

    func testTableDirectivesAcceptVariableColumnWidths() throws {
        let bordered = try KianParser().parse("""
        @表(列幅=1,2,3; 先頭行=中央) {
        | 左 | 中 | 右 |
        | --- | :---: | ---: |
        | あ | い | う |
        }
        """)
        guard case .table(let borderedTable) = bordered.blocks[0] else { return XCTFail() }
        XCTAssertEqual(borderedTable.columnWidthsInCharacters ?? [], [1, 2, 3])
        XCTAssertEqual(borderedTable.firstRowAlignment, .center)
    }

    func testColumnWidthCountMustMatchTable() {
        XCTAssertThrowsError(try KianParser().parse("""
        @表(列幅=1,2) {
        | 一 | 二 | 三 |
        | --- | --- | --- |
        | あ | い | う |
        }
        """))
    }

    func testLegalDocumentSpecificDirectivesWereRemoved() {
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
    }

    func testTabIntervalsAcceptAnyCountAndPreserveTabFields() throws {
        let document = try KianParser().parse("""
        @タブ(1,2,3,4,5,6,7,8,9,10,11,12) {
        \t原　告\t株式会社架空商事
        \t上記代表者代表取締役\t架　空　花　子
        }
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.tabIntervalsInCharacters, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(block.lines[0].cells.count, 3)
        XCTAssertEqual(block.lines[1].cells.count, 3)
    }

    func testTabbedFieldsPreserveIntentionalFullwidthSpaces() throws {
        let document = try KianParser().parse("""
        @タブ(1,7) {
        　訴訟物の価額\t１００万円
        }
        """)
        guard case .tabbed(let block) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(block.lines[0].cells[0].map(\.text).joined(), "　訴訟物の価額")
    }
}
