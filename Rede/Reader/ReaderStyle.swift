import SwiftUI
import os

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

    var family: String? {
        switch self {
        case .original: nil
        case .system: "-apple-system"
        case .pingfang: "\"PingFang SC\""
        }
    }

    var defaultWeight: Int? {
        switch self {
        case .original: nil
        case .system: 300
        case .pingfang: 300
        }
    }

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

    struct Palette {
        let background: String
        let text: String
    }

    // 浅色下“默认”为 nil，沿用书自带样式；深色下书的样式不可用，每项都必须给出具体颜色
    func palette(for scheme: ColorScheme) -> Palette? {
        switch (self, scheme) {
        case (.original, .light): nil
        case (.original, _): Palette(background: "#1e1e1e", text: "#d0d0d0")
        case (.grey, .light): Palette(background: "#e5e5e5", text: "#2f2c28")
        case (.grey, _): Palette(background: "#2b2b2b", text: "#c8c8c8")
        case (.sepia, .light): Palette(background: "#f4ecd8", text: "#2f2c28")
        case (.sepia, _): Palette(background: "#2a2620", text: "#d6cdb8")
        }
    }

    func swatch(for scheme: ColorScheme) -> Color {
        Color(hex: palette(for: scheme)?.background ?? "#ffffff")
    }
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
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

    var file: String? {
        switch self {
        case .none: nil
        case .bamboo: "leaf.svg"
        }
    }

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
    var fontScale: Int
    var font: ReaderFont
    var fontWeights: [ReaderFont: Int]
    var lineSpacing: Spacing
    var paraSpacing: Spacing
    var background: BackgroundColor
    var pattern: BackgroundPattern

    static let fontScaleRange = 50...300
    static let fontScaleStep = 10
    static let `default` = ReaderStyle(fontScale: 100, font: .original, fontWeights: [:],
                                      lineSpacing: .standard, paraSpacing: .standard,
                                      background: .original, pattern: .none)

    var fontWeight: Int? {
        get { font.defaultWeight.map { fontWeights[font] ?? $0 } }
        set { fontWeights[font] = newValue }
    }

    // 浅色用 --RS__textColor，会被书自带样式覆盖；深色用 --USER__textColor 强制覆盖书内颜色。
    // 两个键始终都要给出，不用的传空串，JS 端据此移除旧值
    func cssVariables(for scheme: ColorScheme) -> [String: String] {
        let palette = background.palette(for: scheme)
        let forced = scheme == .dark
        return [
            "--USER__fontSize": "\(fontScale)%",
            "--USER__fontFamily": font.family ?? "",
            "--USER__fontWeight": fontWeight.map(String.init) ?? "",
            "--USER__lineHeight": "\(lineSpacing.lineHeight)",
            "--USER__paraSpacing": "\(paraSpacing.paraSpacing)rem",
            "--RS__textColor": forced ? "" : palette?.text ?? "",
            "--USER__textColor": forced ? palette?.text ?? "" : "",
            "--reader-bg": palette?.background ?? "",
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
    private static let log = Logger(subsystem: "Rede", category: "Settings")

    var readerStyle: ReaderStyle { didSet { save() } }

    var appearance: Appearance {
        didSet {
            NSApp.appearance = appearance.nsAppearance
            save()
        }
    }

    private struct Snapshot: Codable {
        var readerStyle: ReaderStyle?
        var appearance: Appearance?
    }

    private init() {
        let snapshot = (try? Data(contentsOf: AppPaths.settings))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        readerStyle = snapshot?.readerStyle ?? .default
        appearance = snapshot?.appearance ?? .system
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.settings.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Snapshot(readerStyle: readerStyle, appearance: appearance))
                .write(to: AppPaths.settings, options: .atomic)
        } catch {
            Self.log.error("保存设置失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
