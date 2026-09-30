import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EpubFile: FileDocument, Transferable {
    static let readableContentTypes: [UTType] = [.epub]
    let data: Data
    let name: String   // 导出时的文件名

    // 书的文件还没从 iCloud 同步下来时为 nil
    init?(_ book: Book) {
        guard let data = try? book.epubData() else { return nil }
        self.data = data
        name = book.exportName
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    // 分享需要一个按书名命名的文件，写到临时目录
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .epub) { file in
            let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(component: file.name)
            try file.data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
