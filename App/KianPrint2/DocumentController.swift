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
    @Published var zoom: CGFloat = 0.9

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
        panel.title = "Kian Markdown文書を開く"
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
