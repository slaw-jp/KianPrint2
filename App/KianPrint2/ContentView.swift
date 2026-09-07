import AppKit
import KianPrintCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: DocumentController

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let message = controller.message {
                HStack(spacing: 8) {
                    Image(systemName: message.hasPrefix("PDFを書き出しました") ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(message).lineLimit(2)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            pagePreview
        }
        .navigationTitle(controller.displayName)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("開く", systemImage: "folder") { controller.showOpenPanel() }
            Button("PDFを書き出す", systemImage: "square.and.arrow.up") { controller.showExportPanel() }
                .disabled(controller.fileURL == nil)
            Button("再読み込み", systemImage: "arrow.clockwise") { controller.reload() }
                .disabled(controller.fileURL == nil)
            Button("mi.appで編集", systemImage: "pencil") { controller.editInMi() }
                .disabled(controller.fileURL == nil)
            Spacer()
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $controller.zoom, in: 0.45...1.6, step: 0.05)
                .frame(width: 150)
            Image(systemName: "plus.magnifyingglass")
            Text("\(Int(controller.zoom * 100))%")
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
        .padding(12)
    }

    private var pagePreview: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 24) {
                ForEach(Array(controller.layout.pages.enumerated()), id: \.offset) { _, page in
                    PageRepresentable(page: page, zoom: controller.zoom)
                        .frame(width: page.size.width * controller.zoom, height: page.size.height * controller.zoom)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: NSColor(calibratedWhite: 0.82, alpha: 1)))
    }
}

private struct PageRepresentable: NSViewRepresentable {
    var page: KianPage
    var zoom: CGFloat

    func makeNSView(context: Context) -> PageCanvasView { PageCanvasView() }

    func updateNSView(_ view: PageCanvasView, context: Context) {
        view.page = page
        view.zoom = zoom
        view.needsDisplay = true
    }
}

private final class PageCanvasView: NSView {
    var page: KianPage?
    var zoom: CGFloat = 1
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: zoom, y: zoom)
        KianRenderer().draw(page: page, in: context)
        context.restoreGState()
    }
}
