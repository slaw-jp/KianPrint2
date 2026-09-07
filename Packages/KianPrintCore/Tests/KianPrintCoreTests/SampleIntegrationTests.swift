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
        XCTAssertEqual(urls.count, 7)
        for url in urls {
            let source = try String(contentsOf: url, encoding: .utf8)
            let document = try KianParser().parse(source)
            let layout = KianLayoutEngine().layout(document)
            XCTAssertFalse(layout.pages.isEmpty, url.lastPathComponent)
            let pdf = try KianPDFExporter.data(for: layout)
            XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)), url.lastPathComponent)
        }
    }
}
