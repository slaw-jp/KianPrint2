import CoreText
import XCTest
@testable import KianPrintCore

final class KinsokuTests: XCTestCase {
    private let settings = KianSettings()
    private let pairs = [("(", ")"), ("[", "]"), ("{", "}"), ("（", "）"),
                         ("［", "］"), ("｛", "｝"), ("「", "」"), ("『", "』"),
                         ("【", "】"), ("〈", "〉"), ("《", "》"), ("｢", "｣")]

    private func attributed(_ source: String) -> NSAttributedString {
        KianTypography.attributedString(from: [KianInline(text: source)], settings: settings)
    }

    func testReportedCourtParagraphKeepsFullwidthClosingParenOffLineStart() throws {
        let prefix = String(repeating: "あ", count: 31)
        let source = "１　ああああ\r\n(1)　\(prefix)（ああ）ああああ"
        let layout = KianLayoutEngine().layout(try KianParser().parse(source))
        let texts = layout.pages.flatMap(\.commands).compactMap { command -> KianPlacedText? in
            guard case .text(let text) = command else { return nil }
            return text
        }
        XCTAssertEqual(texts.map { $0.text.string }, ["１　ああああ", "(1)　\(prefix)（ああ）", "ああああ"])
        XCTAssertEqual(texts[1].origin.x, settings.leftMargin + settings.fontSize, accuracy: 0.001)
        XCTAssertEqual(texts[2].origin.x, settings.leftMargin + 2 * settings.fontSize, accuracy: 0.001)
        XCTAssertEqual(texts[2].origin.y - texts[1].origin.y, settings.lineAdvance, accuracy: 0.001)
        let pdf = try KianPDFExporter.data(for: layout)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
    }

    func testClosingBracketVariantsAtMeasuredWidthBoundary() {
        let prefix = "あいうえ"
        let boundary = KianTypography.width(of: attributed(prefix))
        for (_, closing) in pairs {
            for delta: CGFloat in [-0.001, 0, 0.001] {
                let source = prefix + closing + "かき"
                let lines = KianLineBreaker().breakLines(attributed(source), width: boundary + delta)
                XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
                XCTAssertFalse(lines.dropFirst().contains { $0.attributedText.string.hasPrefix(closing) }, closing)
                if delta >= 0 {
                    XCTAssertTrue(lines[0].attributedText.string.contains(closing), closing)
                } else {
                    XCTAssertEqual(lines[0].attributedText.string, "あいう", closing)
                }
            }
        }
    }

    func testOpeningBracketVariantsAtMeasuredWidthBoundary() {
        for (opening, _) in pairs {
            let prefix = "あいう" + opening
            let boundary = KianTypography.width(of: attributed(prefix))
            for delta: CGFloat in [-0.001, 0, 0.001] {
                let source = prefix + "かきく"
                let lines = KianLineBreaker().breakLines(attributed(source), width: boundary + delta)
                XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
                XCTAssertFalse(lines.dropLast().contains { $0.attributedText.string.hasSuffix(opening) }, opening)
            }
        }
    }

    func testLatinWordAdjustmentDoesNotLeaveOpeningBracketAtLineEnd() {
        let source = "あ「ABCDE終"
        let width = KianTypography.width(of: attributed("あ「AB"))
        let lines = KianLineBreaker().breakLines(attributed(source), width: width)
        XCTAssertEqual(lines[0].attributedText.string, "あ")
        XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
        XCTAssertFalse(lines.dropLast().contains { $0.attributedText.string.hasSuffix("「") })
    }

    func testConsecutiveClosingMarksUseBoundedHangingAndBacktracking() {
        let source = "あいうえ」』、。かきくけ"
        let width: CGFloat = 48
        let lines = KianLineBreaker().breakLines(attributed(source), width: width)
        XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
        XCTAssertEqual(lines[0].attributedText.string, "あいう")
        for line in lines {
            XCTAssertLessThanOrEqual(line.width, width + settings.fontSize + 0.001)
        }
        for line in lines.dropFirst() {
            XCTAssertFalse("」』、。".contains(line.attributedText.string.first!))
        }
    }

    func testSingleCommaAndPeriodStillHangAtCourtFrameEdge() {
        for mark in ["、", "。"] {
            let prefix = String(repeating: "あ", count: 37)
            let lines = KianLineBreaker().breakLines(attributed(prefix + mark + "次"), width: settings.paragraphContentWidth)
            XCTAssertEqual(lines.map { $0.attributedText.string }, [prefix + mark, "次"])
            XCTAssertGreaterThan(lines[0].width, settings.paragraphContentWidth)
            XCTAssertLessThanOrEqual(lines[0].width, settings.paragraphContentWidth + settings.fontSize)
        }
    }

    func testProhibitedSmallKanaAndRepeatMarksAtSeveralWidths() {
        for mark in ["ゃ", "ョ", "ゕ", "ゖ", "々", "ー", "ゝ", "ㇰ"] {
            for width: CGFloat in [12, 24, 48, 72] {
                let source = "あいうえ" + mark + "かきくけ"
                let lines = KianLineBreaker().breakLines(attributed(source), width: width)
                XCTAssertEqual(lines.map { $0.attributedText.string }.joined(), source)
                XCTAssertFalse(lines.dropFirst().contains { $0.attributedText.string.hasPrefix(mark) }, mark)
            }
        }
    }

    func testUnbreakableBracketGroupInNarrowFrameStillMakesProgress() {
        let source = "（（甲））乙"
        let lines = KianLineBreaker().breakLines(attributed(source), width: 1)
        XCTAssertEqual(lines.map { $0.attributedText.string }, ["（（甲））", "乙"])
    }

    func testExplicitNewlineIsNotJoinedToResolveProhibition() {
        let lines = KianLineBreaker().breakLines(attributed("あ\n）い"), width: 100)
        XCTAssertEqual(lines.map { $0.attributedText.string }, ["あ", "）い"])
    }

    func testTabOrphanAdjustmentDoesNotOverrideKinsoku() throws {
        for source in ["あいうえ）か", "あいう「えか"] {
            let document = try KianParser().parse("@tab(5)left\n\(source)@end")
            let layout = KianLayoutEngine().layout(document)
            let lines = layout.pages.flatMap(\.commands).compactMap { command -> String? in
                guard case .text(let text) = command else { return nil }
                return text.text.string
            }
            XCTAssertEqual(lines.joined(), source)
            XCTAssertFalse(lines.dropFirst().contains { $0.hasPrefix("）") })
            XCTAssertFalse(lines.dropLast().contains { $0.hasSuffix("「") })
        }
    }
}
