import Foundation
import XCTest
@testable import KianPrintCore

final class SampleIntegrationTests: XCTestCase {
    func testEveryPublicSampleParsesLayoutsAndExportsPDF() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let samples = root.appendingPathComponent("Samples")
        let urls = try FileManager.default.contentsOfDirectory(at: samples, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
        XCTAssertEqual(urls.count, 5)
        for url in urls {
            let source = try String(contentsOf: url, encoding: .utf8)
            let digitsExcludedFromProseCheck = source
                .replacingOccurrences(of: #"\([0-9]+\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"列幅=[0-9,.]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"R[0-9.]+"#, with: "", options: .regularExpression)
            if url.lastPathComponent == "証拠説明書.txt" {
                XCTAssertTrue(source.contains("R8.4.1"))
            }
            XCTAssertNil(
                digitsExcludedFromProseCheck.range(of: #"[0-9]"#, options: .regularExpression),
                "法律文書サンプルの通常本文には半角数字を使わない: \(url.lastPathComponent)"
            )
            let document = try KianParser().parse(source)
            let layout = KianLayoutEngine().layout(document)
            XCTAssertFalse(layout.pages.isEmpty, url.lastPathComponent)
            let pdf = try KianPDFExporter.data(for: layout)
            XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)), url.lastPathComponent)
        }
    }
}
