import AppKit
import KianPrintCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentController: ObservableObject {
    static let shared = DocumentController()

    @Published private(set) var fileURL: URL?
    @Published private(set) var layout: KianLayout
    @Published private(set) var message: String?
    @Published private(set) var warnings: [String] = []
    @Published var zoom: CGFloat = 1.0

    private let parser = KianParser()
    private let layoutEngine = KianLayoutEngine()
    private let monitor = FileMonitor()
    private var securityScopedURL: URL?

    private init() {
        let empty = KianDocument(settings: KianSettings(), blocks: [])
        layout = layoutEngine.layout(empty)
    }

    var displayName: String { fileURL?.lastPathComponent ?? "ファイルが開かれていません" }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "KianPrint2文書を開く"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func open(url: URL) {
        guard url.pathExtension.lowercased() == "txt" else {
            message = "β版では .txt ファイルを開いてください。"
            return
        }
        stopSecurityScope()
        if url.startAccessingSecurityScopedResource() { securityScopedURL = url }
        fileURL = url
        monitor.start(watching: url) { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        guard let fileURL else { return }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard let source = String(data: data, encoding: .utf8) else {
                throw KianIssue(message: "UTF-8のテキストとして読み込めません。")
            }
            let document = try parser.parse(source)
            let nextLayout = layoutEngine.layout(document)
            layout = nextLayout
            warnings = document.issues.map(\.description)
            message = document.issues.first?.description
            NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
        } catch {
            // The last valid layout intentionally remains visible.
            message = (error as? KianIssue)?.description ?? error.localizedDescription
        }
    }

    func showExportPanel() {
        guard let fileURL else { return }
        let panel = NSSavePanel()
        panel.title = "PDFを書き出す"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let data = try KianPDFExporter.data(for: layout)
            try data.write(to: destination, options: .atomic)
            message = "PDFを書き出しました: \(destination.lastPathComponent)"
        } catch {
            message = "PDFを書き出せませんでした: \(error.localizedDescription)"
        }
    }

    func printDocument() {
        guard let fileURL else { return }

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.paperSize = layout.pages.first?.size ?? CGSize(
            width: layout.settings.paperWidth,
            height: layout.settings.paperHeight
        )
        printInfo.orientation = .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .clip
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.scalingFactor = 1

        let printView = KianPrintView(layout: layout)
        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.jobTitle = fileURL.deletingPathExtension().lastPathComponent
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if operation.run() {
            message = "印刷を開始しました。"
        }
    }

    func editInMi() {
        guard let fileURL else { return }
        let candidates = [
            URL(fileURLWithPath: "/Applications/mi.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/mi.app")
        ]
        guard let applicationURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            message = "mi.appが見つかりません。"
            return
        }
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.message = "mi.appで開けませんでした: \(error.localizedDescription)" }
            }
        }
    }

    private func stopSecurityScope() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    deinit { securityScopedURL?.stopAccessingSecurityScopedResource() }
}

private final class KianPrintView: NSView {
    private let pages: [KianPage]
    private let pageSize: CGSize
    private let renderer = KianRenderer()

    init(layout: KianLayout) {
        pages = layout.pages
        pageSize = layout.pages.first?.size ?? CGSize(
            width: layout.settings.paperWidth,
            height: layout.settings.paperHeight
        )
        super.init(frame: CGRect(
            origin: .zero,
            size: CGSize(width: pageSize.width, height: pageSize.height * CGFloat(pages.count))
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pages.count)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        guard pages.indices.contains(page - 1) else { return .zero }
        return pageRect(at: page - 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for (index, page) in pages.enumerated() {
            let pageRect = pageRect(at: index)
            guard dirtyRect.intersects(pageRect) else { continue }
            context.saveGState()
            context.translateBy(x: pageRect.minX, y: pageRect.minY)
            renderer.draw(page: page, in: context)
            context.restoreGState()
        }
    }

    private func pageRect(at index: Int) -> CGRect {
        CGRect(x: 0, y: CGFloat(index) * pageSize.height, width: pageSize.width, height: pageSize.height)
    }
}
