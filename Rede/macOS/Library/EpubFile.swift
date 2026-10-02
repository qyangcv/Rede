import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EpubFile: FileDocument {
    static let readableContentTypes: [UTType] = [.epub]
    let data: Data

    init?(_ book: Book) {
        guard let data = try? book.epubData() else { return nil }
        self.data = data
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
