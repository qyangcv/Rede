import Foundation
import Kanna
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

struct ChapterAnchors: Codable {
    var anchors: [String: Int]
}

nonisolated extension EpubBook {
    func textStats() -> (chapterLengths: [Int], wordCount: Int) {
        var wordCount = 0
        let lengths = model.spine.map { item -> Int in
            guard let data = try? fetcher.data(at: item.path),
                  let xml = try? XML(xml: data, encoding: .utf8)
            else { return 0 }
            let texts = xml.xpath("//*[local-name()='body']//text()").compactMap { $0.text }
            wordCount += countWords(texts.joined(separator: " "))
            return texts.reduce(0) { $0 + $1.utf16.count }
        }
        return (lengths, wordCount)
    }
}

nonisolated private func countWords(_ text: String) -> Int {
    var count = 0
    var inWord = false
    for scalar in text.unicodeScalars {
        if scalar.properties.isIdeographic {
            count += 1
            inWord = false
        } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
            if !inWord { count += 1 }
            inWord = true
        } else {
            inWord = false
        }
    }
    return count
}

@MainActor
final class ChapterLengthIndexer {
    static let shared = ChapterLengthIndexer()
    private var running: Set<String> = []

    func ensure(_ book: Book, in context: ModelContext) {
        guard book.chapterLengths.isEmpty || book.wordCount == nil,
              running.insert(book.id).inserted else { return }
        let id = book.id, url = book.url
        Task {
            let stats = try? await Self.compute(url)
            running.remove(id)
            guard let stats,
                  let book = try? context.fetch(FetchDescriptor<Book>(
                      predicate: #Predicate { $0.id == id })).first
            else { return }
            book.chapterLengths = stats.chapterLengths
            book.wordCount = stats.wordCount
            try? context.save()
        }
    }

    @concurrent
    nonisolated private static func compute(_ url: URL) async throws -> (chapterLengths: [Int], wordCount: Int) {
        try parseEpub(at: url).textStats()
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
