enum ReaderTitle: String, CaseIterable, Identifiable, Codable {
    case hidden, book, chapter

    var id: Self { self }

    var name: String {
        switch self {
        case .hidden: "隐藏"
        case .book: "书名"
        case .chapter: "章节名"
        }
    }
}
