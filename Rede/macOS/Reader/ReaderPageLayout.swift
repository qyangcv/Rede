enum ReaderPageLayout: String, CaseIterable, Identifiable, Codable {
    case auto, single, double

    var id: Self { self }

    var name: String {
        switch self {
        case .auto: "自动"
        case .single: "单页"
        case .double: "双页"
        }
    }

    var cssValue: String {
        switch self {
        case .auto: "auto"
        case .single: "1"
        case .double: "2"
        }
    }
}
