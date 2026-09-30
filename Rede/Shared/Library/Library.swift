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
    static let settings = root.appending(components: ".settings", "settings.json")
    static let fonts = root.appending(component: ".fonts", directoryHint: .isDirectory)
}

// 同步开关：书库在启动时按设置创建，本次启动内不再改变
enum CloudSync {
    static let container = "iCloud.dev.qyang.Rede"
    static let isActive = Settings.shared.iCloudSync
}

// 字段都带默认值、不用唯一约束、关系可选：这是 CloudKit 同步对模型的要求
@Model
final class Book {
    // epub 文件 SHA-256 的前 8 位十六进制。CloudKit 不支持唯一约束，
    // 两台设备在同步前各自导入同一本书会产生 id 相同的记录，由 BookMerger 合并
    var id: String = ""
    var name: String = ""
    var author: String = ""
    var date: Date = Date.now
    var position: ReadingPosition?
    var chapterLengths: [Int] = []   // 每章字符数，用于计算全书阅读百分比
    var wordCount: Int?
    var lastRead: Date?
    @Attribute(.externalStorage) var cover: Data?   // 缩略封面，JPEG
    // EPUB 本体单独一张表：翻页只改 Book，不会带着整本书重新上传；同步时它可能比 Book 晚到
    @Relationship(deleteRule: .cascade, inverse: \BookFile.book) var file: BookFile?

    init(id: String, name: String, author: String, date: Date = .now) {
        self.id = id
        self.name = name
        self.author = author
        self.date = date
    }

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
            return try ModelContainer(for: Book.self, BookFile.self, configurations: configuration)
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }()
}

enum BookImporter {
    // 封面缩略图的长边像素，够 3 倍屏上的书架卡片用
    private static let coverSize = 600

    @discardableResult
    static func importBook(from source: URL, into context: ModelContext) throws -> Book {
        // 文件选择器、拖放、"打开方式"传来的 URL 可能在沙盒外，读之前要先申请访问权限
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
        context.delete(book)
        try context.save()
    }
}

// 两台设备在同步前各自导入同一本书，会出现 id 相同的记录：保留最早导入的一条，
// 阅读进度取最近读过的那条
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
