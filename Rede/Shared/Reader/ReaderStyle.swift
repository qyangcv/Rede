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

enum HighlightColor: String, CaseIterable, Identifiable, Codable {
    case yellow, green, blue, pink, purple

    var id: Self { self }

    var name: String {
        switch self {
        case .yellow: "鹅黄"
        case .green: "竹绿"
        case .blue: "霁蓝"
        case .pink: "绯粉"
        case .purple: "丁香紫"
        }
    }

    func color(for scheme: ColorScheme) -> String {
        switch (self, scheme) {
        case (.yellow, .dark): "rgba(255, 200, 60, 0.28)"
        case (.yellow, _): "rgba(255, 204, 0, 0.48)"
        case (.green, .dark): "rgba(74, 198, 128, 0.26)"
        case (.green, _): "rgba(76, 195, 120, 0.38)"
        case (.blue, .dark): "rgba(88, 166, 255, 0.28)"
        case (.blue, _): "rgba(82, 168, 245, 0.36)"
        case (.pink, .dark): "rgba(245, 118, 152, 0.28)"
        case (.pink, _): "rgba(242, 112, 146, 0.34)"
        case (.purple, .dark): "rgba(182, 138, 252, 0.28)"
        case (.purple, _): "rgba(174, 126, 242, 0.34)"
        }
    }

    func note(for scheme: ColorScheme) -> String {
        switch (self, scheme) {
        case (.yellow, .dark): "#E0A030"
        case (.yellow, _): "#D08000"
        case (.green, .dark): "#62C48A"
        case (.green, _): "#2B8A52"
        case (.blue, .dark): "#6AAFE6"
        case (.blue, _): "#2B74B8"
        case (.pink, .dark): "#E87A9A"
        case (.pink, _): "#C44B6C"
        case (.purple, .dark): "#BA94F5"
        case (.purple, _): "#7B4EC2"
        }
    }

    var swatchHex: String {
        switch self {
        case .yellow: "#F5C838"
        case .green: "#4CC378"
        case .blue: "#52A8F5"
        case .pink: "#F27092"
        case .purple: "#AE7EF2"
        }
    }

    var swatch: Color { Color(hex: swatchHex) }

    var accent: Color {
        switch self {
        case .yellow: Color(hex: "#E0A030")
        case .green: Color(hex: "#3DA869")
        case .blue: Color(hex: "#4595E0")
        case .pink: Color(hex: "#DF6285")
        case .purple: Color(hex: "#9B6CE0")
        }
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
        var vars: [String: String] = [
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
        ]
        for color in HighlightColor.allCases {
            vars["--reader-highlight-\(color.rawValue)"] = color.color(for: scheme)
            vars["--reader-note-\(color.rawValue)"] = color.note(for: scheme)
        }
        return vars
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
