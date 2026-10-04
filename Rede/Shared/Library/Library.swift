import Foundation
import SwiftData
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum AppPaths {
    #if DEBUG
    static let root = URL.applicationSupportDirectory
        .appending(component: "Rede-Debug", directoryHint: .isDirectory)
    #else
    static let root = URL.applicationSupportDirectory
        .appending(component: "Rede", directoryHint: .isDirectory)
    #endif
    static let library = root.appending(component: ".library", directoryHint: .isDirectory)
    static let store = library.appending(component: "library.store")
    static let settings = root.appending(components: ".settings", "settings.json")
    static let fonts = root.appending(component: ".fonts", directoryHint: .isDirectory)
}

enum CloudSync {
    static let container = "iCloud.dev.qyang.Rede"
    static let isActive = Settings.shared.iCloudSync
}

@Model
final class Book {
    var id: String = ""
    var name: String = ""
    var author: String = ""
    var date: Date = Date.now
    var position: ReadingPosition?
    var chapterLengths: [Int] = []
    var wordCount: Int?
    var lastRead: Date?
    @Attribute(.externalStorage) var cover: Data?
    @Relationship(deleteRule: .cascade, inverse: \BookFile.book) var file: BookFile?

    init(id: String, name: String, author: String, date: Date = .now) {
        self.id = id
        self.name = name
        self.author = author
        self.date = date
    }

    var progress: Double? {
        position.flatMap { progress(chapter: $0.chapter, offset: $0.offset) }
    }

    func progress(chapter: Int, offset: Int) -> Double? {
        guard chapter < chapterLengths.count else { return nil }
        let total = chapterLengths.reduce(0, +)
        guard total > 0 else { return nil }
        let read = chapterLengths[..<chapter].reduce(0, +) + max(offset, 0)
        return min(Double(read) / Double(total), 1)
    }
    var exportName: String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + ".epub"
    }

    func epubData() throws -> Data {
        guard let data = file?.data else { throw LibraryError.fileNotSynced }
        return data
    }

    func epub() throws -> EpubBook {
        try parseEpub(epubData())
    }
}

@Model
final class BookFile {
    @Attribute(.externalStorage) var data = Data()
    var book: Book?

    init(data: Data) {
        self.data = data
    }
}

enum LibraryError: LocalizedError {
    case fileNotSynced

    var errorDescription: String? {
        switch self {
        case .fileNotSynced: "这本书还没有从 iCloud 下载完成，请稍后再试"
        }
    }
}

extension ModelContainer {
    static let library: ModelContainer = {
        do {
            try FileManager.default.createDirectory(at: AppPaths.library,
                                                    withIntermediateDirectories: true)
            let configuration = ModelConfiguration(
                url: AppPaths.store,
                cloudKitDatabase: CloudSync.isActive ? .private(CloudSync.container) : .none)
            return try ModelContainer(for: Book.self, BookFile.self, Annotation.self, configurations: configuration)
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }()
}

enum BookImporter {
    private static let coverSize = 600

    @discardableResult
    static func importBook(from source: URL, into context: ModelContext) throws -> Book {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        let id = fileID(of: data)
        let existing = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        if let book = try context.fetch(existing).first { return book }

        let epub = try parseEpub(data)
        let title = epub.model.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Book(id: id,
                        name: title.isEmpty ? source.deletingPathExtension().lastPathComponent : title,
                        author: epub.model.metadata.author)
        book.cover = thumbnail(of: epub)
        book.file = BookFile(data: data)

        context.insert(book)
        try context.save()
        ChapterLengthIndexer.shared.ensure(book, in: context)
        return book
    }

    private static func fileID(of data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func thumbnail(of epub: EpubBook) -> Data? {
        guard let cover = epub.model.cover,
              let data = try? epub.fetcher.data(at: cover.path),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: coverSize,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

enum BookRemover {
    static func remove(_ book: Book, from context: ModelContext) throws {
        let id = book.id
        let annotations = try context.fetch(FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookID == id }))
        for annotation in annotations { context.delete(annotation) }
        context.delete(book)
        try context.save()
    }
}

enum BookMerger {
    static func merge(in context: ModelContext) {
        guard let books = try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.date)]))
        else { return }
        var kept: [String: Book] = [:]
        for book in books {
            guard let first = kept[book.id] else {
                kept[book.id] = book
                continue
            }
            if (book.lastRead ?? .distantPast) > (first.lastRead ?? .distantPast) {
                first.position = book.position
                first.lastRead = book.lastRead
            }
            context.delete(book)
        }
        if context.hasChanges { try? context.save() }
    }
}
