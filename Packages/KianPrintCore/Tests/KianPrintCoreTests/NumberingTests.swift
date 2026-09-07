import XCTest
@testable import KianPrintCore

final class NumberingTests: XCTestCase {
    func testLegacyHierarchyWithArticleDocument() {
        let lines = ["第１条　目的", "第１　総則", "１　本文", "(1)　本文", "ア　本文", "(ア)　本文", "ａ　本文", "(a)　本文"]
        var recognizer = LegalNumberingRecognizer(allLines: lines)
        let values = lines.map { recognizer.indent(for: $0) }
        XCTAssertEqual(values.map(\.level), [2, 2, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(values.map(\.outdent), [2, 2, 1, 1, 1, 1, 1, 1])
    }

    func testLegacyAdjustmentWithoutDaiHeadingAndContinuation() {
        let lines = ["１　本文", "　　継続段落"]
        var recognizer = LegalNumberingRecognizer(allLines: lines)
        XCTAssertEqual(recognizer.indent(for: lines[0]).level, 1)
        let continuation = recognizer.indent(for: lines[1])
        XCTAssertEqual(continuation, KianIndent(level: 1, outdent: 1))
    }

    func testCircledNumberKeepsSiblingIndent() {
        let lines = ["１　本文", "①　項目", "②　項目"]
        var recognizer = LegalNumberingRecognizer(allLines: lines)
        _ = recognizer.indent(for: lines[0])
        let first = recognizer.indent(for: lines[1])
        let second = recognizer.indent(for: lines[2])
        XCTAssertEqual(first.level, second.level)
    }
}
