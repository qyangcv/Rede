enum ReaderWindowMode: String, CaseIterable, Identifiable, Codable {
    case single, multiple

    var id: Self { self }

    var name: String {
        switch self {
        case .single: "替换当前书籍"
        case .multiple: "在新窗口打开"
        }
    }
}
