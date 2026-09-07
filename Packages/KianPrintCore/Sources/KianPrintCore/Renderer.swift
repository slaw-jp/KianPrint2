import CoreGraphics
import CoreText
import Foundation

public struct KianRenderer {
    public init() {}

    /// Draws a pre-laid-out page. Coordinates in `KianPage` always start at
    /// the page's top-left, so preview and PDF consume exactly the same commands.
    public func draw(page: KianPage, in context: CGContext) {
        context.saveGState()
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)
        for command in page.commands {
            switch command {
            case .text(let placed):
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: placed.origin.x, y: placed.origin.y + placed.ascent)
                context.scaleBy(x: 1, y: -1)
                let line = CTLineCreateWithAttributedString(placed.text)
                CTLineDraw(line, context)
                context.restoreGState()
            case .line(let from, let to, let weight):
                context.saveGState()
                context.setStrokeColor(CGColor(gray: 0, alpha: 1))
                context.setLineWidth(weight == .thin ? 0.5 : 1.5)
                context.move(to: from)
                context.addLine(to: to)
                context.strokePath()
                context.restoreGState()
            case .rectangle(let rectangle, let weight):
                context.saveGState()
                context.setStrokeColor(CGColor(gray: 0, alpha: 1))
                context.setLineWidth(weight == .thin ? 0.5 : 1.5)
                context.stroke(rectangle)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }
}

public enum KianPDFExporter {
    public static func data(for layout: KianLayout) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw KianIssue(message: "PDF出力先を作成できませんでした。")
        }
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: layout.settings.paperWidth, height: layout.settings.paperHeight))
        let metadata: [CFString: Any] = [
            kCGPDFContextCreator: "KianPrint2",
            kCGPDFContextTitle: "KianPrint2 document"
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw KianIssue(message: "PDF描画コンテキストを作成できませんでした。")
        }
        let renderer = KianRenderer()
        for page in layout.pages {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: page.size.height)
            context.scaleBy(x: 1, y: -1)
            renderer.draw(page: page, in: context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
