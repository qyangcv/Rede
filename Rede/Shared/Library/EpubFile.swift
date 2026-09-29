import SwiftUI
import UniformTypeIdentifiers

struct EpubFile: FileDocument {
    static let readableContentTypes: [UTType] = [.epub]
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}