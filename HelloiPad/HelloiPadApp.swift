import SwiftUI

@main
struct HelloiPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument()) { configuration in
            let title = configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
            NavigationStack {
                EditorView()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}