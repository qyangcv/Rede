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

enum LibrarySchema {
    static let models: [any PersistentModel.Type] = [Book.self, BookFile.self, BookCategory.self,
                                                  Annotation.self, ReadingSpan.self]
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
    var category: BookCategory?
    var categoryUpdatedAt: Date?
    var sourceFormat: String?
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

    var progressText: String? {
        progress?.formatted(.percent.precision(.fractionLength(0...1)).rounded(rule: .down))
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

    func assign(to category: BookCategory?) {
        guard self.category?.id != category?.id else { return }
        self.category = category
        categoryUpdatedAt = .now
    }
}

struct BookDetails {
    struct Field: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let metadata: EpubMetadata?
    let fileSize: Int?
    let readingTime: Duration?

    init(book: Book, in context: ModelContext) {
        readingTime = try? context.readingTime(of: book)
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let data = try? book.epubData()
        metadata = try? data.map(parseEpub)?.model.metadata
        fileSize = data?.count
    }

    static func fields(for book: Book, details: BookDetails?) -> [Field] {
        let values: [(String, String?)] = [
            ("书名", book.name),
            ("作者", book.author),
            ("出版社", details?.metadata?.publisher),
            ("出版日期", details?.metadata?.date),
            ("ISBN", details?.metadata?.isbn),
            ("原始格式", book.sourceFormat?.uppercased()),
            ("EPUB 版本", details?.metadata?.version),
            ("文件大小", details?.fileSize.map { Int64($0).formatted(.byteCount(style: .file)) }),
            ("字数", book.wordCount?.formatted()),
            ("导入时间", book.date.formatted(date: .abbreviated, time: .shortened)),
            ("最后阅读", book.lastRead?.formatted(date: .abbreviated, time: .shortened)),
            ("阅读时长", details?.readingTime?.readingText),
        ]
        return values.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Field(label: label, value: value)
        }
    }
}

@Model
final class BookCategory {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var sortIndex: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Book.category) var books: [Book]?

    init(name: String) {
        self.name = name
    }
}

enum BookCategories {
    struct Selection {
        let commonID: UUID?
        let canRemove: Bool

        init(_ books: [Book]) {
            let firstID = books.first?.category?.id
            if let firstID {
                commonID = books.dropFirst().allSatisfy { $0.category?.id == firstID } ? firstID : nil
                canRemove = true
            } else {
                commonID = nil
                canRemove = books.dropFirst().contains { $0.category != nil }
            }
        }
    }

    static let libraryName = "我的书库"
    static let sortDescriptors = [SortDescriptor(\BookCategory.sortIndex),
                                  SortDescriptor(\BookCategory.createdAt),
                                  SortDescriptor(\BookCategory.id)]

    static func create(named name: String, books: [Book] = [], in context: ModelContext) throws -> BookCategory {
        let category = BookCategory(name: try validatedName(name, in: context))
        var descriptor = FetchDescriptor<BookCategory>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        descriptor.fetchLimit = 1
        category.sortIndex = (try context.fetch(descriptor).first?.sortIndex ?? -1) + 1
        context.insert(category)
        for book in books { book.assign(to: category) }
        try context.save()
        return category
    }

    static func reorder(_ categories: [BookCategory], in context: ModelContext) throws {
        for (index, category) in categories.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try context.save()
    }

    static func rename(_ category: BookCategory, to name: String, in context: ModelContext) throws {
        category.name = try validatedName(name, excluding: category.id, in: context)
        try context.save()
    }

    static func assign(_ books: [Book], to category: BookCategory?, in context: ModelContext) throws {
        for book in books { book.assign(to: category) }
        try context.save()
    }

    static func remove(_ category: BookCategory, from context: ModelContext) throws {
        for book in category.books ?? [] { book.assign(to: nil) }
        context.delete(category)
        try context.save()
    }

    private static func validatedName(_ name: String, excluding id: UUID? = nil,
                                      in context: ModelContext) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryError.emptyName }
        let categories = try context.fetch(FetchDescriptor<BookCategory>())
        guard name.localizedCaseInsensitiveCompare(libraryName) != .orderedSame,
              !categories.contains(where: {
                  $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
              }) else { throw CategoryError.duplicateName }
        return name
    }
}

enum CategoryError: LocalizedError {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入分类名称"
        case .duplicateName: "已存在同名分类，请使用其他名称"
        }
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
            return try ModelContainer(for: Schema(LibrarySchema.models), configurations: configuration)
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }()
}

enum BookImporter {
    private static let coverSize = 600
    nonisolated static let supportedExtensions: Set<String> = ["epub", "azw3", "mobi"]
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [.epub]
        if let azw3 = UTType(filenameExtension: "azw3") { types.append(azw3) }
        if let mobi = UTType(filenameExtension: "mobi") { types.append(mobi) }
        return types
    }()

    nonisolated static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func importBooks(from urls: [URL], into context: ModelContext, category: BookCategory?) -> [String] {
        var errors: [String] = []
        for url in urls {
            do {
                try importBook(from: url, into: context, category: category)
            } catch {
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return errors
    }

    @discardableResult
    static func importBook(from source: URL, into context: ModelContext,
                           category: BookCategory? = nil) throws -> Book {
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }

        let rawData = try Data(contentsOf: source)
        let id = fileID(of: rawData)
        let existing = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        if let book = try context.fetch(existing).first {
            if let category { try BookCategories.assign([book], to: category, in: context) }
            return book
        }

        let fileExtension = source.pathExtension.lowercased()
        let data = try normalizedEpubData(from: rawData, fileExtension: fileExtension)
        let epub = try parseEpub(data)
        guard !epub.model.spine.isEmpty else { throw MobiConversionError.emptyContent }
        let filename = source.deletingPathExtension().lastPathComponent
        let metadataTitle = epub.model.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
        let useMetadataTitle = Settings.shared.useMetadataTitle
        #else
        let useMetadataTitle = true
        #endif
        let name = useMetadataTitle
            ? (metadataTitle.isEmpty ? filename : metadataTitle)
            : (filename.isEmpty ? metadataTitle : filename)
        let book = Book(id: id,
                        name: name,
                        author: epub.model.metadata.author)
        book.sourceFormat = fileExtension.isEmpty ? nil : fileExtension
        book.cover = thumbnail(of: epub)
        book.file = BookFile(data: data)

        context.insert(book)
        book.assign(to: category)
        try context.save()
        ChapterLengthIndexer.shared.ensure(book, in: context)
        return book
    }

    private static func normalizedEpubData(from data: Data, fileExtension: String) throws -> Data {
        switch fileExtension {
        case "azw3", "mobi":
            return try MobiToEpub.convert(data)
        default:
            return data
        }
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
        let spans = try context.fetch(FetchDescriptor<ReadingSpan>(
            predicate: #Predicate { $0.bookID == id }))
        for span in spans { context.delete(span) }
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
            if (book.categoryUpdatedAt ?? .distantPast) > (first.categoryUpdatedAt ?? .distantPast) {
                first.category = book.category
                first.categoryUpdatedAt = book.categoryUpdatedAt
            }
            context.delete(book)
        }
        if context.hasChanges { try? context.save() }
    }
}

extension ModelContext {
    func books(_ ids: [Book.ID]) throws -> [Book] {
        try fetch(FetchDescriptor<Book>(predicate: #Predicate { ids.contains($0.id) }))
    }
}
