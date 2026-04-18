import SwiftUI
import UniformTypeIdentifiers

@main
struct HelloiPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument()) { configuration in
            let title = configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
            let text = configuration.document.text
            NavigationStack {
                EditorView(initialText: text)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}