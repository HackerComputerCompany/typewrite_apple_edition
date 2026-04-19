// TypewriteAppleEditionApp.swift
//
// App entry point. Uses DocumentGroup with ReferenceFileDocument so that
// the system handles file creation, opening, and saving. The document's
// text property is synced on every keystroke via autosave debounce.

import SwiftUI

@main
struct TypewriteAppleEditionApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PlainTextDocument() }) { file in
            EditorView(document: file.document)
        }
    }
}
