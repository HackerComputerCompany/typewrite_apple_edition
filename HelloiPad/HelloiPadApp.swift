import SwiftUI

@main
struct HelloiPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PlainTextDocument() }) { file in
            EditorView(document: file.document)
        }
    }
}