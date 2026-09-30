import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EpubFile: FileDocument, Transferable {
    static let readableContentTypes: [UTType] = [.epub]
    let url: URL
    let name: String   // 导出时的文件名

    init(_ book: Book) {
        url = book.url
        name = book.exportName
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }

    // 库里的书统一叫 book.epub，分享前复制一份按书名命名（APFS 上复制是克隆，不占额外空间）
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .epub) { file in
            let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(component: file.name)
            try FileManager.default.copyItem(at: file.url, to: copy)
            return SentTransferredFile(copy)
        }
    }
}
