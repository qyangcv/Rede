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

struct AnnotationMark: Equatable {
    let id: String
    let kind: Annotation.Kind
    let chapter: Int
    let start: Int
    let end: Int
    let hasNote: Bool

    init?(_ annotation: Annotation) {
        guard let kind = annotation.kind else { return nil }
        id = annotation.id
        self.kind = kind
        chapter = annotation.chapter
        start = annotation.start
        end = annotation.end
        hasNote = !annotation.note.isEmpty
    }

    var jsObject: [String: Any] {
        ["id": id, "kind": kind.rawValue, "chapter": chapter, "start": start, "end": end, "note": hasNote]
    }
}

struct TextSelection: Decodable {
    let chapter: Int
    let start: Int
    let end: Int
    let text: String
    let rect: WebRect
}

final class AnnotationStore {
    private static let log = Logger(subsystem: "Rede", category: "Annotation")

    private let bookID: String
    private let context: ModelContext

    init(bookID: String, context: ModelContext) {
        self.bookID = bookID
        self.context = context
    }

    func annotations() -> [Annotation] {
        let id = bookID
        let descriptor = FetchDescriptor<Annotation>(
            predicate: #Predicate { $0.bookID == id },
            sortBy: [SortDescriptor(\.chapter), SortDescriptor(\.start)])
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.log.error("读取标注失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func addBookmark(chapter: Int, offset: Int, text: String) {
        context.insert(Annotation(bookID: bookID, kind: .bookmark, chapter: chapter,
                                  start: offset, end: offset, text: text))
        save()
    }

    func addHighlight(_ selection: TextSelection) -> Annotation {
        let annotation = Annotation(bookID: bookID, kind: .highlight, chapter: selection.chapter,
                                    start: selection.start, end: selection.end, text: selection.text)
        context.insert(annotation)
        save()
        return annotation
    }

    func setNote(_ note: String, of annotation: Annotation) {
        guard annotation.note != note else { return }
        annotation.note = note
        save()
    }

    func delete(ids: [String]) {
        for annotation in annotations() where ids.contains(annotation.id) {
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
