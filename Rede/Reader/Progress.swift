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
