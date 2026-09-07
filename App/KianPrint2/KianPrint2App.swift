import AppKit
import SwiftUI

@main
struct KianPrint2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var documentController = DocumentController.shared

    var body: some Scene {
        Window("KianPrint2", id: "main") {
            ContentView(controller: documentController)
                .frame(minWidth: 380, minHeight: 320)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開く…") { documentController.showOpenPanel() }
                    .keyboardShortcut("o")
                Button("再読み込み") { documentController.reload() }
                    .keyboardShortcut("r")

                Divider()

                Button("PDFを書き出す…") { documentController.showExportPanel() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(documentController.fileURL == nil)
                Button("mi.appで編集") { documentController.editInMi() }
                    .disabled(documentController.fileURL == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in DocumentController.shared.open(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
