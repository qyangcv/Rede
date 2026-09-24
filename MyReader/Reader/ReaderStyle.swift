import SwiftUI

// CodingKeyRepresentable 让以它为 key 的字典编码成 JSON 对象，而不是扁平数组
enum ReaderFont: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable {
    case original, system, pingfang

    var id: Self { self }

    var name: String {
        switch self {
        case .original: "默认"
        case .system: "系统"
        case .pingfang: "苹方"
        }
    }

    // CSS font-family 值，nil 表示沿用书内字体；-apple-system 是关键字，不能加引号
    var family: String? {
        switch self {
        case .original: nil
        case .system: "-apple-system"
        case .pingfang: "\"PingFang SC\""
        }
    }

    // 默认字重，nil 表示字重由书决定
    var defaultWeight: Int? {
        switch self {
        case .original: nil
        case .system: 300
        case .pingfang: 300
        }
    }

    // 可选字重：系统字体（SF + 系统私有的可变苹方）支持连续字重，按细粒度取值；
    // 公开的 PingFang SC 只有静态字形，只列出适合正文的几档
    var weights: [Int] {
        switch self {
        case .original: []
        case .system: Array(stride(from: 200, through: 500, by: 25))
        case .pingfang: [200, 300, 400, 500]
        }
    }
}

enum Spacing: String, CaseIterable, Identifiable, Codable {
    case compact, standard, loose

    var id: Self { self }

    var name: String {
        switch self {
        case .compact: "小"
        case .standard: "中"
        case .loose: "大"
        }
    }

    private var metrics: (lineHeight: Double, paraSpacing: Double) {
        switch self {
        case .compact: (1.4, 0.4)
        case .standard: (1.6, 0.9)
        case .loose: (1.9, 1.5)
        }
    }

    var lineHeight: Double { metrics.lineHeight }
    var paraSpacing: Double { metrics.paraSpacing }
}

enum BackgroundColor: String, CaseIterable, Identifiable, Codable {
    case original, grey, sepia

    var id: Self { self }

    var name: String {
        switch self {
        case .original: "默认"
        case .grey: "浅灰"
        case .sepia: "米黄"
        }
    }

    // nil 表示跟随书：外壳页退回白色，章节根元素不设底色
    var color: String? {
        switch self {
        case .original: nil
        case .grey: "#e5e5e5"
        case .sepia: "#f4ecd8"
        }
    }

    // 与背景配套的正文颜色；ReadiumCSS 要求背景色和文字色成对设置，才能压住书内自带的配色；
    // 默认时交还给书和 ReadiumCSS
    var textColor: String? { color == nil ? nil : "#2f2c28" }

    // 面板色块：默认按实际呈现的白色显示
    var swatch: Color { Color(hex: color ?? "#ffffff") }
}

enum BackgroundPattern: String, CaseIterable, Identifiable, Codable {
    case none, bamboo

    var id: Self { self }

    var name: String {
        switch self {
        case .none: "默认"
        case .bamboo: "竹叶"
        }
    }

    // 图案文件：外壳页经 myreader:// 加载，样式面板的缩略图读同一个文件
    var file: String? {
        switch self {
        case .none: nil
        case .bamboo: "leaf.svg"
        }
    }

    // 外壳页的 base URL 是书的 scheme，相对路径会解析错，必须给绝对 URL
    var css: String {
        guard let file, let url = AppResourceSchemeHandler.url(for: file) else { return "none" }
        return "url(\"\(url.absoluteString)\")"
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

struct ReaderStyle: Equatable {
    var fontScale: Int      // 相对书本字号的百分比，由 ReadiumCSS 以 zoom 等比缩放
    var font: ReaderFont
    var fontWeights: [ReaderFont: Int]  // 用户按字体调整过的字重，未调整的取字体默认值
    var lineSpacing: Spacing
    var paraSpacing: Spacing
    var background: BackgroundColor
    var pattern: BackgroundPattern

    static let fontScaleRange = 50...300
    static let fontScaleStep = 10
    static let `default` = ReaderStyle(fontScale: 100, font: .original, fontWeights: [:],
                                      lineSpacing: .standard, paraSpacing: .standard,
                                      background: .original, pattern: .none)

    // 当前字体的字重，nil 表示字重由书决定
    var fontWeight: Int? {
        get { font.defaultWeight.map { fontWeights[font] ?? $0 } }
        set { fontWeights[font] = newValue }
    }

    // --USER__* 写到章节文档的 :root，交给 ReadiumCSS；--reader-bg / --reader-pattern 由外壳页绘制
    var cssVariables: [String: String] {
        [
            "--USER__fontSize": "\(fontScale)%",
            // 空值会被 style.setProperty 移除，ReadiumCSS 随之退回书内字体
            "--USER__fontFamily": font.family ?? "",
            "--USER__fontWeight": fontWeight.map(String.init) ?? "",
            "--USER__lineHeight": "\(lineSpacing.lineHeight)",
            "--USER__paraSpacing": "\(paraSpacing.paraSpacing)rem",
            "--RS__textColor": background.textColor ?? "",
            "--reader-bg": background.color ?? "",
            "--reader-pattern": pattern.css,
        ]
    }
}

extension ReaderStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case fontScale, font, fontWeights, lineSpacing, paraSpacing, background, pattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReaderStyle.default
        fontScale = try container.decodeIfPresent(Int.self, forKey: .fontScale) ?? fallback.fontScale
        font = try container.decodeIfPresent(ReaderFont.self, forKey: .font) ?? fallback.font
        fontWeights = try container.decodeIfPresent([ReaderFont: Int].self, forKey: .fontWeights) ?? fallback.fontWeights
        lineSpacing = try container.decodeIfPresent(Spacing.self, forKey: .lineSpacing) ?? fallback.lineSpacing
        paraSpacing = try container.decodeIfPresent(Spacing.self, forKey: .paraSpacing) ?? fallback.paraSpacing
        background = try container.decodeIfPresent(BackgroundColor.self, forKey: .background) ?? fallback.background
        pattern = try container.decodeIfPresent(BackgroundPattern.self, forKey: .pattern) ?? fallback.pattern
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(font, forKey: .font)
        try container.encode(fontWeights, forKey: .fontWeights)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(paraSpacing, forKey: .paraSpacing)
        try container.encode(background, forKey: .background)
        try container.encode(pattern, forKey: .pattern)
    }

    init?(rawValue: String) {
        guard let value = try? JSONDecoder().decode(ReaderStyle.self, from: Data(rawValue.utf8)) else {
            return nil
        }
        self = value
    }

    var rawValue: String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

@Observable
final class Settings {
    static let shared = Settings()

    var readerStyle: ReaderStyle { didSet { save() } }

    private struct Snapshot: Codable {
        var readerStyle: ReaderStyle?
    }

    private init() {
        let snapshot = (try? Data(contentsOf: AppPaths.settings))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        readerStyle = snapshot?.readerStyle ?? .default
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.settings.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Snapshot(readerStyle: readerStyle))
                .write(to: AppPaths.settings, options: .atomic)
        } catch {
            print("保存设置失败：\(error)")
        }
    }
}
