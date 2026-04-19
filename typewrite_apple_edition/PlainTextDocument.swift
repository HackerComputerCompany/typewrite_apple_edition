// PlainTextDocument.swift
//
// ReferenceFileDocument for .txt files. Using a reference type (class)
// instead of a value type (struct) so that EditorView can mutate
// document.text in-place and the autosave system picks up changes.
//
// The @Published text property is written to on every keystroke
// (debounced via EditorView.scheduleAutosave). When the app backgrounds,
// saveNow() is called immediately.
//
// snapshot() + fileWrapper() provide the serialization path that iOS calls
// to persist the document to disk.

import SwiftUI
import UniformTypeIdentifiers

class PlainTextDocument: ReferenceFileDocument, ObservableObject {
    @Published var text: String

    init(text: String = "") {
        self.text = text
    }

    static var readableContentTypes: [UTType] { [.plainText] }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = String(decoding: data, as: UTF8.self)
    }

    func snapshot(contentType: UTType) throws -> Data {
        Data(text.utf8)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}