import SwiftUI
import UniformTypeIdentifiers

@main
struct HelloiPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument()) { configuration in
            EditorView(initialText: configuration.document.text)
        }
    }
}