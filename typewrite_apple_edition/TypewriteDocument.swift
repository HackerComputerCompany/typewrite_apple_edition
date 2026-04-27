// TypewriteDocument.swift
//
// `ReferenceFileDocument` wrapper: primary save format is `TwBinaryArchiveV1` (`.twd` / com…typewrite),
// with plain UTF-8 text import/export (colours and session data are not preserved in .txt).

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Must match `com.hackercomputercompany.typewrite.document` in `TypewriteUTIExport.plist` (`UTExportedTypeDeclarations`).
    static var typewriteDocument: UTType {
        UTType(exportedAs: "com.hackercomputercompany.typewrite.document", conformingTo: .data)
    }
}

final class TypewriteDocument: ReferenceFileDocument, ObservableObject {
    /// On-disk or last-saved bytes (binary `TWDB` for native saves).
    @Published var fileData: Data
    /// Most recent `TwDoc.fullText()` for .txt snapshot / export.
    @Published var lastPlainTextForExport: String
    /// When `true`, `fileData` is raw UTF-8 that should be read with `TwDoc.load` (no `TWDB` header).
    @Published var openedAsPlainText: Bool
    @Published var sessionFromLastFile: TwSessionMetadata

    static var readableContentTypes: [UTType] { [.typewriteDocument, .plainText, .utf8PlainText] }
    static var writableContentTypes: [UTType] { [.typewriteDocument, .plainText, .utf8PlainText] }

    init() {
        self.fileData = (try? TwBinaryArchiveV1.encode(doc: TwDoc(), session: .empty)) ?? Data()
        self.lastPlainTextForExport = ""
        self.openedAsPlainText = false
        self.sessionFromLastFile = .empty
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, !data.isEmpty else {
            self.fileData = (try? TwBinaryArchiveV1.encode(doc: TwDoc(), session: .empty)) ?? Data()
            self.openedAsPlainText = true
            self.sessionFromLastFile = .empty
            self.lastPlainTextForExport = ""
            return
        }
        if data.count >= 4, String(data: data[0..<4], encoding: .ascii) == TwBinaryArchiveV1.magic {
            self.fileData = data
            self.openedAsPlainText = false
            self.sessionFromLastFile = (try? TwBinaryArchiveV1.decode(data).1) ?? .empty
        } else {
            self.fileData = data
            self.openedAsPlainText = true
            self.sessionFromLastFile = .empty
        }
        self.lastPlainTextForExport = ""
    }

    /// Called from `EditorView` on autosave with the current canvas model and session tracker stats.
    func updateSnapshot(doc: TwDoc, session: TwSessionMetadata) {
        if let d = try? TwBinaryArchiveV1.encode(doc: doc, session: session) {
            fileData = d
        }
        lastPlainTextForExport = doc.fullText()
        openedAsPlainText = false
    }

    func snapshot(contentType: UTType) throws -> Data {
        if contentType == .plainText || contentType == .utf8PlainText {
            return Data(lastPlainTextForExport.utf8)
        }
        return fileData
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
