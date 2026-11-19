import Foundation

enum LibraryLayout: String, CaseIterable, Identifiable, Codable {
    case grid, list

    var id: Self { self }

    var name: String {
        switch self {
        case .grid: "卡片"
        case .list: "列表"
        }
    }

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable, Codable {
    case imported, lastRead, title, author, wordCount, progress, readingTime

    var id: Self { self }

    var name: String {
        switch self {
        case .imported: "导入时间"
        case .lastRead: "阅读时间"
        case .title: "书名"
        case .author: "作者名"
        case .wordCount: "字数"
        case .progress: "进度"
        case .readingTime: "阅读时长"
        }
    }

    var defaultOrder: SortOrder {
        switch self {
        case .title, .author: .forward
        default: .reverse
        }
    }
}
