import Foundation
import SwiftData
import AppKit

enum AppPaths {
    static let root = URL(filePath: "/Users/yang/code/MyReader", directoryHint: .isDirectory)
    static let library = root.appending(component: ".library", directoryHint: .isDirectory)
    static let store = library.appending(component: "library.store")
    static let books = library.appending(component: "books", directoryHint: .isDirectory)
    static let settings = root.appending(components: ".settings", "settings.json")
}

@Model
final class Book {
    @Attribute(.unique) var name: String
    var author: String
    var date: Date

    init(name: String, author: String, date: Date = .now) {
        self.name = name
        self.author = author
        self.date = date
    }
    
    var parent: URL { AppPaths.books.appending(component: name, directoryHint: .isDirectory) }
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
        let fm = FileManager.default
        let name = source.deletingPathExtension().lastPathComponent
        let book = Book(name: name, author: "")
        try fm.createDirectory(at: book.parent, withIntermediateDirectories: true)
        
        if fm.fileExists(atPath: book.url.path(percentEncoded: false)) {
            try fm.removeItem(at: book.url)
        }
        try fm.copyItem(at: source, to: book.url)
        
        let epub = try parseEpub(at: book.url)
        book.author = epub.model.metadata.author
        
        saveCover(of: epub, to: book.cover)
        
        context.insert(book)
        try context.save()
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
