import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// 只记书的 ID，真正分享时才在后台读出 EPUB：菜单随卡片一起构建，在这里读整本书既浪费，
// 书被删除后还会读到已脱离 context 的 BookFile 而崩溃
nonisolated struct EpubShareItem: Transferable {
    let id: PersistentIdentifier
    let container: ModelContainer
    let name: String   // 分享出去的文件名

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .epub) { item in
            let context = ModelContext(item.container)
            guard let book = context.model(for: item.id) as? Book else {
                throw LibraryError.fileNotSynced
            }
            let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(component: item.name)
            try book.epubData().write(to: url)
            return SentTransferredFile(url)
        }
    }
}
