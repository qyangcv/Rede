import Foundation
import SwiftData
import AppKit
import CryptoKit

enum AppPaths {
    #if DEBUG
    static let root = URL(filePath: #filePath)   // .../MyReader/Library/Library.swift
        .deletingLastPathComponent()             // .../MyReader/Library
        .deletingLastPathComponent()             // .../MyReader
        .deletingLastPathComponent()             // 仓库根目录
    #else
    static let root = URL.applicationSupportDirectory
        .appending(component: "MyReader", directoryHint: .isDirectory)
    #endif
    static let library = root.appending(component: ".library", directoryHint: .isDirectory)
    static let store = library.appending(component: "library.store")
    static let books = library.appending(component: "books", directoryHint: .isDirectory)
    static let settings = root.appending(components: ".settings", "settings.json")
}

@Model
final class Book {
    @Attribute(.unique) var id: String   // epub 文件 SHA-256 的前 8 位十六进制
    var name: String
    var author: String
    var date: Date
    var position: ReadingPosition?

    init(id: String, name: String, author: String, date: Date = .now) {
        self.id = id
        self.name = name
        self.author = author
        self.date = date
    }
    
    var parent: URL { AppPaths.books.appending(component: id, directoryHint: .isDirectory) }
    var url: URL { parent.appending(component: "book.epub") }
    var cover: URL { parent.appending(component: "cover.jpg") }
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
    static func importBook(from source: URL, into context: ModelContext) throws {
        let id = try fileID(of: source)
        let existing = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        guard try context.fetchCount(existing) == 0 else { return }

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
    }

    private static func fileID(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func saveCover(of epub: EpubBook, to url: URL) {
        guard let cover = epub.model.cover,
              let data =  try? epub.fetcher.data(at: cover.path) else { return }
        
        let jpeg: Data?
        if cover.mediaType == "image/jpeg" {
            jpeg = data
        } else {
            let bitmap = NSBitmapImageRep(data: data)
            jpeg = bitmap?.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
        }
        
        guard let jpeg else { return }
        try? jpeg.write(to: url)
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
