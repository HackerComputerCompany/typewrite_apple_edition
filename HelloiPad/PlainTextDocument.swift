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