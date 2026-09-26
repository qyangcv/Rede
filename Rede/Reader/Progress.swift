import Foundation
import SwiftData
import os

struct ReadingPosition: Codable, Equatable {
    var chapter: Int
    var offset: Int
    var total: Int
    var ratio: Double

    var jsObject: [String: Any] {
        ["chapter": chapter, "offset": offset, "ratio": ratio]
    }
}

struct PageInfo: Codable, Equatable {
    var page: Int
    var pageCount: Int
}

nonisolated extension EpubBook {
    func chapterLengths() -> [Int] {
        model.spine.map { item in
            guard let data = try? fetcher.data(at: item.path),
                  let xml = try? XMLDocument(data: data, options: .nodePreserveWhitespace),
                  let nodes = try? xml.nodes(forXPath: "//*[local-name()='body']//text()")
            else { return 0 }
            return nodes.reduce(0) { $0 + ($1.stringValue?.utf16.count ?? 0) }
        }
    }
}

@MainActor
final class ChapterLengthIndexer {
    static let shared = ChapterLengthIndexer()
    private var running: Set<String> = []

    func ensure(_ book: Book, in context: ModelContext) {
        guard book.chapterLengths.isEmpty, running.insert(book.id).inserted else { return }
        let id = book.id, url = book.url
        Task {
            let lengths = try? await Self.compute(url)
            running.remove(id)
            guard let lengths,
                  let book = try? context.fetch(FetchDescriptor<Book>(
                      predicate: #Predicate { $0.id == id })).first
            else { return }
            book.chapterLengths = lengths
            try? context.save()
        }
    }

    @concurrent
    nonisolated private static func compute(_ url: URL) async throws -> [Int] {
        try parseEpub(at: url).chapterLengths()
    }
}

@MainActor
final class ProgressStore {
    private static let delay: Duration = .seconds(2)
    private static let log = Logger(subsystem: "Rede", category: "ReadingProgress")

    private let book: Book
    private let context: ModelContext
    private var pending: ReadingPosition?
    private var task: Task<Void, Never>?

    init(book: Book, context: ModelContext) {
        self.book = book
        self.context = context
    }

    func record(_ position: ReadingPosition) {
        guard position != pending else { return }
        pending = position
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let position = pending else { return }
        pending = nil

        book.position = position
        do {
            try context.save()
        } catch {
            Self.log.error("保存阅读进度失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
