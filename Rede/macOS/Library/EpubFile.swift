import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EpubFile: FileDocument {
    static let readableContentTypes: [UTType] = [.epub]
    let data: Data

    // 书的文件还没从 iCloud 同步下来时为 nil
    init?(_ book: Book) {
        guard let data = try? book.epubData() else { return nil }
        self.data = data
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
