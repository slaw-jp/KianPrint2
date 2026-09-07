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

    func testTableSemanticsAndInlineMarkup() throws {
        let source = """
        # 証拠説明書
        | 号証 | 標目 | 作成年月日 | 作成者 | 立証趣旨 | 備考 |
        | :---: | --- | :---: | --- | --- | --- |
        | 甲1 | **契約書** 原本 | R8.1.1 | 架空太郎 | *契約成立* | |
        """
        let document = try KianParser().parse(source)
        guard case .table(let table) = document.blocks.first(where: { if case .table = $0 { return true }; return false }) else {
            return XCTFail("table not parsed")
        }
        XCTAssertEqual(table.kind, .evidenceList)
        XCTAssertTrue(table.rows[0].cells[1].inlines.contains(where: \.bold))
        XCTAssertTrue(table.rows[0].cells[4].inlines.contains(where: \.italic))
    }

    func testEvidenceOpinionAndEmptyInheritedCell() throws {
        let source = """
        # 証拠意見書
        | 号証 | 対象部分 | 意見 | 備考 |
        | --- | --- | :---: | --- |
        | 甲1 | 全部 | 同意 | |
        | | 一部 | 不同意 | |
        """
        let document = try KianParser().parse(source)
        guard case .table(let table) = document.blocks[1] else { return XCTFail() }
        XCTAssertEqual(table.kind, .evidenceOpinion)
        XCTAssertEqual(table.rows[1].cells[0].plainText, "")
    }

    func testEvidenceRequestShortNameHeadingAndDirective() throws {
        let automatic = try KianParser().parse("""
        # 証拠調請求書
        | 項目 | 内容 |
        | --- | --- |
        | 架空 | 架空 |
        """)
        guard case .table(let automaticTable) = automatic.blocks[1] else { return XCTFail() }
        XCTAssertEqual(automaticTable.kind, .evidenceRequest)

        let explicit = try KianParser().parse("""
        @証拠調請求書 {
        | 項目 | 内容 |
        | --- | --- |
        | 架空 | 架空 |
        }
        """)
        guard case .table(let explicitTable) = explicit.blocks[0] else { return XCTFail() }
        XCTAssertEqual(explicitTable.kind, .evidenceRequest)
    }

    func testExplicitHeadingTakesPriorityOverTableColumnInference() throws {
        let document = try KianParser().parse("""
        # 証拠意見書
        | 号証 | 標目 | 立証趣旨 |
        | --- | --- | --- |
        | 甲1 | 架空 | 架空 |
        """)
        guard case .table(let table) = document.blocks[1] else { return XCTFail() }
        XCTAssertEqual(table.kind, .evidenceOpinion)
    }

    func testEvidenceDocumentTitleAppliesAfterFirstPageMetadata() throws {
        let document = try KianParser().parse("""
        # 証拠意見書
        @右揃え {
        令和８年９月７日
        }
        架空地方裁判所民事部　御中
        @右配置(職印) {
        被告訴訟代理人弁護士　見　本　次　郎
        }
        | 項目 | 内容 |
        | --- | --- |
        | 架空 | 架空 |
        """)
        guard case .table(let table) = document.blocks.last else { return XCTFail() }
        XCTAssertEqual(table.kind, .evidenceOpinion)
    }

    func testSealArgumentReservesThirtyMillimeters() throws {
        let document = try KianParser().parse("""
        @右配置(職印) {
        原告訴訟代理人弁護士　架　空　太　郎
        }
        """)
        guard case .blockBox(let box) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(box.trailingInset, 30 * KianSettings.pointsPerMillimeter, accuracy: 0.001)
    }

    func testEvidenceListRecognitionAcceptsFiledDocumentHeaders() throws {
        let document = try KianParser().parse("""
        | 符号<br>番号 | 標目 |  | 作成年月<br>日 | 作成者 | 立証趣旨 |
        | --- | --- | --- | --- | --- | --- |
        | 甲１ | 契約書 | 原本 | 令和８年 | 原告 | 契約の成立 |
        """)
        guard case .table(let table) = document.blocks[0] else { return XCTFail() }
        XCTAssertEqual(table.kind, .evidenceList)
    }
}
