import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EpubFile: FileDocument {
    static let readableContentTypes: [UTType] = [.epub]
    let name: String
    let data: Data

    @MainActor init(_ book: Book) throws {
        name = book.exportName
        data = try book.epubData()
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
