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
    var start: Int?
    var excerpt: String
    var bookmarks: [String]
}

struct ProgressReport: Decodable {
    let position: ReadingPosition
    let page: PageInfo
    let anchors: [String: Int]

    private enum CodingKeys: String, CodingKey { case anchors }

    init(from decoder: any Decoder) throws {
        position = try ReadingPosition(from: decoder)
        page = try PageInfo(from: decoder)
        anchors = try decoder.container(keyedBy: CodingKeys.self).decode([String: Int].self, forKey: .anchors)
    }

    init?(_ body: Any) {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let report = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = report
    }
}

nonisolated extension EpubBook {
    func textStats() -> (chapterLengths: [Int], wordCount: Int) {
        let media = "local-name()='img' or local-name()='svg' or local-name()='video'"
        let body = "//*[local-name()='body']"
        var wordCount = 0
        let lengths = model.spine.map { item -> Int in
            guard let data = try? fetcher.data(at: item.path),
                  let xml = try? XML(xml: data, encoding: .utf8)
            else { return 0 }
            let texts = xml.xpath("\(body)//text()[not(ancestor::*[\(media)])]").compactMap { $0.text }
            let mediaCount = xml.xpath("\(body)//*[(\(media)) and not(ancestor::*[\(media)])]").count
            wordCount += countWords(texts.joined(separator: " "))
            return texts.reduce(0) { $0 + $1.utf16.count } + mediaCount
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
              let data = try? book.epubData(),
              running.insert(book.id).inserted else { return }
        let id = book.id
        Task {
            let stats = try? await Self.compute(data)
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
    nonisolated private static func compute(_ data: Data) async throws -> (chapterLengths: [Int], wordCount: Int) {
        try parseEpub(data).textStats()
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
        guard book.modelContext != nil else { return }

        book.position = position
        do {
            try context.save()
        } catch {
            Self.log.error("保存阅读进度失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
