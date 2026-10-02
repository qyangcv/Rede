import SwiftUI
import SwiftData
import UniformTypeIdentifiers

nonisolated struct EpubShareItem: Transferable {
    let id: PersistentIdentifier
    let container: ModelContainer
    let name: String

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
