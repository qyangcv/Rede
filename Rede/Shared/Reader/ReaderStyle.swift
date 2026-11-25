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
    case neutral, warm, sage, gray

    var id: Self { self }

    var name: String {
        switch self {
        case .neutral: "霜"
        case .warm: "笺"
        case .sage: "青"
        case .gray: "砚"
        }
    }

    func color(for scheme: ColorScheme) -> String {
        switch (self, scheme) {
        case (.neutral, .dark): "#1A1A1A"
        case (.neutral, _): "#F8F8F8"
        case (.warm, .dark): "#211E16"
        case (.warm, _): "#F5F0E6"
        case (.sage, .dark): "#1C2117"
        case (.sage, _): "#DFE5D9"
        case (.gray, .dark): "#303030"
        case (.gray, _): "#DEDEDE"
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
        scheme == .dark ? "rgba(255, 200, 60, 0.28)" : "rgba(255, 204, 0, 0.48)"
    }

    static func note(for scheme: ColorScheme) -> String {
        scheme == .dark ? "#E0A030" : "#D08000"
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

    static let fontScaleRange = 80...300
    static let fontScaleStep = 5
    static let `default` = ReaderStyle(fontScale: 100, font: .original, fontWeights: [:],
                                      lineSpacing: .standard, paraSpacing: .standard,
                                      background: .neutral)

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
            "--reader-highlight": HighlightColor.color(for: scheme),
            "--reader-note": HighlightColor.note(for: scheme),
        ]
    }
}

extension ReaderStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case fontScale, font, fontWeights, lineSpacing, paraSpacing, background
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
    }

}
