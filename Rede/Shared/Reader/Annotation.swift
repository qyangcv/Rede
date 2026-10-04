import Foundation
import SwiftData
import os

@Model
final class Annotation {
    enum Kind: String {
        case bookmark
        case highlight
    }

    var id: String = UUID().uuidString
    var bookID: String = ""
    var kindRaw: String = Kind.highlight.rawValue
    var chapter: Int = 0
    var start: Int = 0
    var end: Int = 0
    var text: String = ""
    var note: String = ""
    var created: Date = Date.now

    init(bookID: String, kind: Kind, chapter: Int, start: Int, end: Int, text: String) {
        self.bookID = bookID
        self.kindRaw = kind.rawValue
        self.chapter = chapter
        self.start = start
        self.end = end
        self.text = text
    }

    var kind: Kind? { Kind(rawValue: kindRaw) }
}

struct BookmarkMark: Equatable {
    let id: String
    let chapter: Int
    let offset: Int

    init(_ annotation: Annotation) {
        id = annotation.id
        chapter = annotation.chapter
        offset = annotation.start
    }

    var jsObject: [String: Any] { ["id": id, "chapter": chapter, "offset": offset] }
}

final class AnnotationStore {
    private static let log = Logger(subsystem: "Rede", category: "Annotation")

    private let bookID: String
    private let context: ModelContext

    init(bookID: String, context: ModelContext) {
        self.bookID = bookID
        self.context = context
    }

    func bookmarks() -> [Annotation] {
        let id = bookID
        let kind = Annotation.Kind.bookmark.rawValue
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookID == id && $0.kindRaw == kind },
            sortBy: [SortDescriptor(\.chapter), SortDescriptor(\.start)])
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.log.error("读取书签失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func addBookmark(chapter: Int, offset: Int, text: String) {
        context.insert(Annotation(bookID: bookID, kind: .bookmark, chapter: chapter,
                                  start: offset, end: offset, text: text))
        save()
    }

    func delete(ids: [String]) {
        for annotation in bookmarks() where ids.contains(annotation.id) {
            context.delete(annotation)
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("保存标注失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
