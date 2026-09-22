import Foundation
import SwiftData

// 阅读位置：以「章内字符偏移」为主锚点，与排版无关；
// ratio 是锚点失效（当前页无可定位文本，如整页插图）时的兜底
struct ReadingPosition: Codable, Equatable {
    var chapter: Int
    var offset: Int
    var total: Int
    var ratio: Double

    var jsObject: [String: Any] {
        ["chapter": chapter, "offset": offset, "ratio": ratio]
    }
}

// 翻页时存入内存，停下 2 秒 / 关窗 / 退出时才写入文件
@MainActor
final class ProgressStore {
    private static let delay: Duration = .seconds(2)

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
            print("保存阅读进度失败：\(error)")
        }
    }
}
