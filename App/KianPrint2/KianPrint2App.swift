import AppKit
import SwiftUI

@main
struct KianPrint2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var documentController = DocumentController.shared

    var body: some Scene {
        WindowGroup {
            ContentView(controller: documentController)
                .frame(minWidth: 760, minHeight: 640)
                .onOpenURL { documentController.open(url: $0) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開く…") { documentController.showOpenPanel() }
                    .keyboardShortcut("o")
                Button("再読み込み") { documentController.reload() }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .saveItem) {
                Button("PDFを書き出す…") { documentController.showExportPanel() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
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
