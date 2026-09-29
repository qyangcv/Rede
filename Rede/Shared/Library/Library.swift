import Foundation
import SwiftData
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum AppPaths {
    #if DEBUG
    // ~/Library/Application\ Support/Rede-Debug
    static let root = URL.applicationSupportDirectory
        .appending(component: "Rede-Debug", directoryHint: .isDirectory)
    #else
    // ~/Library/Application\ Support/Rede
    static let root = URL.applicationSupportDirectory
        .appending(component: "Rede", directoryHint: .isDirectory)
    #endif
    static let library = root.appending(component: ".library", directoryHint: .isDirectory)
    static let store = library.appending(component: "library.store")
    static let books = library.appending(component: "books", directoryHint: .isDirectory)
    static let settings = root.appending(components: ".settings", "settings.json")
    static let fonts = root.appending(component: ".fonts", directoryHint: .isDirectory)
}

@Model
final class Book {
    @Attribute(.unique) var id: String   // epub 文件 SHA-256 的前 8 位十六进制
    var name: String
    var author: String
    var date: Date
    var position: ReadingPosition?
    var chapterLengths: [Int] = []   // 每章字符数，用于计算全书阅读百分比
    var wordCount: Int?
    var lastRead: Date?

    init(id: String, name: String, author: String, date: Date = .now) {
        self.id = id
        self.name = name
        self.author = author
        self.date = date
    }
    
    var parent: URL { AppPaths.books.appending(component: id, directoryHint: .isDirectory) }
    var url: URL { parent.appending(component: "book.epub") }
    var cover: URL { parent.appending(component: "cover.jpg") }

    // 全书阅读百分比 = 当前页首字符之前的字数 / 全书字数；未读或尚未统计字数时为 nil
    var progress: Double? {
        guard let position, position.chapter < chapterLengths.count else { return nil }
        let total = chapterLengths.reduce(0, +)
        guard total > 0 else { return nil }
        let read = chapterLengths[..<position.chapter].reduce(0, +) + max(position.offset, 0)
        return min(Double(read) / Double(total), 1)
    }
    var exportName: String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + ".epub"
    }
}

extension ModelContainer {
    static let localLibrary: ModelContainer = {
        do {
            try FileManager.default.createDirectory(at: AppPaths.library,
                                                    withIntermediateDirectories: true)
            return try ModelContainer(for: Book.self,
                                      configurations: ModelConfiguration(url: AppPaths.store))
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }()
}

enum BookImporter {
    @discardableResult
    static func importBook(from source: URL, into context: ModelContext) throws -> Book {
        // 文件选择器、拖放、"打开方式"传来的 URL 可能在沙盒外，读之前要先申请访问权限
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }

        let id = try fileID(of: source)
        let existing = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        if let book = try context.fetch(existing).first { return book }

        let fm = FileManager.default
        let book = Book(id: id, name: "", author: "")
        try? fm.removeItem(at: book.parent)
        try fm.createDirectory(at: book.parent, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: book.url)
        
        let epub = try parseEpub(at: book.url)
        let title = epub.model.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.name = title.isEmpty ? source.deletingPathExtension().lastPathComponent : title
        book.author = epub.model.metadata.author

        saveCover(of: epub, to: book.cover)

        context.insert(book)
        try context.save()
        ChapterLengthIndexer.shared.ensure(book, in: context)
        return book
    }

    private static func fileID(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func saveCover(of epub: EpubBook, to url: URL) {
        guard let cover = epub.model.cover,
              let data = try? epub.fetcher.data(at: cover.path) else { return }

        let jpeg = cover.mediaType == "image/jpeg" ? data : jpegData(from: data)
        guard let jpeg else { return }
        try? jpeg.write(to: url)
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

enum BookRemover {
    static func remove(_ book: Book, from context: ModelContext) throws {
        let dataPath = book.parent
        try FileManager.default.removeItem(at: dataPath)
        
        context.delete(book)
        try context.save()
    }
}
