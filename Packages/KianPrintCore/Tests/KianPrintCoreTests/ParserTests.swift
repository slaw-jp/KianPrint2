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
        XCTAssertTrue(document.blocks.contains { if case .blockBox = $0 { return true }; return false })
        XCTAssertTrue(document.blocks.contains { if case .pageBreak = $0 { return true }; return false })
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
}
