import SwiftUI

enum Spacing: String, CaseIterable, Identifiable, Codable {
    case compact, snug, standard, relaxed, loose

    var id: Self { self }

    var name: String {
        switch self {
        case .compact: "小"
        case .snug: "较小"
        case .standard: "中"
        case .relaxed: "较大"
        case .loose: "大"
        }
    }

    private var metrics: (lineHeight: Double, paraSpacing: Double) {
        switch self {
        case .compact: (1.4, 0.2)
        case .snug: (1.5, 0.5)
        case .standard: (1.65, 0.8)
        case .relaxed: (1.8, 1.2)
        case .loose: (2.0, 1.6)
        }
    }

    var lineHeight: Double { metrics.lineHeight }
    var paraSpacing: Double { metrics.paraSpacing }
}

enum BackgroundColor: String, CaseIterable, Identifiable, Codable {
    case neutral, warm

    var id: Self { self }

    func name(for scheme: ColorScheme) -> String {
        switch (self, scheme) {
        case (.neutral, .dark): "松烟"
        case (.neutral, _): "霜白"
        case (.warm, .dark): "茶墨"
        case (.warm, _): "米笺"
        }
    }

    func color(for scheme: ColorScheme) -> String {
        switch (self, scheme) {
        case (.neutral, .dark): "#1A1A1A"
        case (.neutral, _): "#F8F8F8"
        case (.warm, .dark): "#211E16"
        case (.warm, _): "#F5F0E6"
        }
    }

    func swatch(for scheme: ColorScheme) -> Color {
        Color(hex: color(for: scheme))
    }
}

enum TextColor {
    static func color(for scheme: ColorScheme) -> String {
        scheme == .dark ? "#D1D1D1" : "#303030"
    }
}

enum LinkColor {
    static let dark = "#7EC4E6"
}

enum HighlightColor {
    static func color(for scheme: ColorScheme) -> String {
        scheme == .dark ? "rgba(255, 200, 60, 0.28)" : "rgba(255, 200, 0, 0.35)"
    }

    static func note(for scheme: ColorScheme) -> String {
        scheme == .dark ? "#E0A030" : "#D08000"
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

    static let fontScaleRange = 80...300
    static let fontScaleStep = 5
    static let `default` = ReaderStyle(fontScale: 100, font: .original, fontWeights: [:],
                                      lineSpacing: .standard, paraSpacing: .standard,
                                      background: .neutral, pattern: .none)

    var fontWeight: Int? {
        get { font.defaultWeight.map { fontWeights[font] ?? $0 } }
        set { fontWeights[font] = newValue }
    }

    func cssVariables(for scheme: ColorScheme) -> [String: String] {
        let text = TextColor.color(for: scheme)
        let forced = scheme == .dark
        return [
            "--USER__fontSize": "\(fontScale)%",
            "--USER__fontFamily": font.family ?? "",
            "--USER__fontWeight": fontWeight.map(String.init) ?? "",
            "--USER__lineHeight": "\(lineSpacing.lineHeight)",
            "--USER__paraSpacing": "\(paraSpacing.paraSpacing)rem",
            "--RS__textColor": forced ? "" : text,
            "--USER__textColor": forced ? text : "",
            "--USER__linkColor": forced ? LinkColor.dark : "",
            "--USER__visitedColor": forced ? LinkColor.dark : "",
            "--reader-bg": background.color(for: scheme),
            "--reader-pattern": pattern.css,
            "--reader-highlight": HighlightColor.color(for: scheme),
            "--reader-note": HighlightColor.note(for: scheme),
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
