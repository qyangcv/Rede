import Foundation
import SwiftData

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