import Foundation

struct BookComparator: SortComparator {
    var key: LibrarySort
    var order: SortOrder
    var readingTimes: [Book.ID: Duration]

    func compare(_ lhs: Book, _ rhs: Book) -> ComparisonResult {
        let result = order == .forward ? primary(lhs, rhs) : primary(rhs, lhs)
        guard result == .orderedSame else { return result }
        let newer = Self.compare(rhs.date, lhs.date)
        return newer == .orderedSame ? Self.compare(lhs.id, rhs.id) : newer
    }

    private func primary(_ lhs: Book, _ rhs: Book) -> ComparisonResult {
        switch key {
        case .imported: Self.compare(lhs.date, rhs.date)
        case .lastRead: Self.compare(lhs.lastRead ?? .distantPast, rhs.lastRead ?? .distantPast)
        case .title: lhs.name.localizedStandardCompare(rhs.name)
        case .author: lhs.author.localizedStandardCompare(rhs.author)
        case .wordCount: Self.compare(lhs.wordCount ?? -1, rhs.wordCount ?? -1)
        case .progress: Self.compare(lhs.progress ?? -1, rhs.progress ?? -1)
        case .readingTime: Self.compare(readingTimes[lhs.id] ?? .zero, readingTimes[rhs.id] ?? .zero)
        }
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }
}
