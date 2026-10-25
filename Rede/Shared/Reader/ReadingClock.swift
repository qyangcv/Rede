import Foundation
import SwiftData
import os

@Model
final class ReadingSpan {
    var id: String = UUID().uuidString
    var bookID: String = ""
    var start: Date = Date.now
    var duration: Double = 0

    init(bookID: String, start: Date, duration: Double) {
        self.bookID = bookID
        self.start = start
        self.duration = duration
    }
}

@MainActor
final class ReadingClock {
    private static let idleLimit: Duration = .seconds(15 * 60)
    private static let minimum: TimeInterval = 10
    private static let log = Logger(subsystem: "Rede", category: "ReadingTime")

    private let bookID: String
    private let context: ModelContext
    private var foreground = false
    private var start: Date?
    private var lastPosition: ReadingPosition?
    private var idleTask: Task<Void, Never>?

    init(bookID: String, context: ModelContext) {
        self.bookID = bookID
        self.context = context
    }

    func setForeground(_ foreground: Bool) {
        guard foreground != self.foreground else { return }
        self.foreground = foreground
        if foreground {
            start = .now
            watchIdle()
        } else {
            stop()
        }
    }

    func record(_ position: ReadingPosition) {
        guard position != lastPosition else { return }
        lastPosition = position
        guard foreground else { return }
        if start == nil { start = .now }
        watchIdle()
    }

    func stop() {
        end(at: .now)
    }

    private func watchIdle() {
        let turn = Date.now
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLimit)
            guard !Task.isCancelled else { return }
            self?.end(at: turn)
        }
    }

    private func end(at end: Date) {
        idleTask?.cancel()
        idleTask = nil
        guard let start else { return }
        self.start = nil
        let duration = end.timeIntervalSince(start)
        guard duration >= Self.minimum else { return }
        context.insert(ReadingSpan(bookID: bookID, start: start, duration: duration))
        do {
            try context.save()
        } catch {
            Self.log.error("保存阅读时长失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

extension ModelContext {
    func readingTime(of book: Book) throws -> Duration {
        let id = book.id
        let spans = try fetch(FetchDescriptor<ReadingSpan>(predicate: #Predicate { $0.bookID == id }))
        return .seconds(spans.reduce(0) { $0 + $1.duration })
    }
}

extension Duration {
    var readingText: String? {
        guard self >= .seconds(60) else { return nil }
        return formatted(.units(allowed: [.hours, .minutes], width: .wide,
                                zeroValueUnits: .hide, fractionalPart: .hide(rounded: .down))
            .locale(Locale(identifier: "zh_Hans")))
    }
}
