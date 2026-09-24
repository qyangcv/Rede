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

    var color: String? {
        switch self {
        case .original: nil
        case .grey: "#e5e5e5"
        case .sepia: "#f4ecd8"
        }
    }

    var textColor: String? { color == nil ? nil : "#2f2c28" }

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

    var cssVariables: [String: String] {
        [
            "--USER__fontSize": "\(fontScale)%",
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
    private static let log = Logger(subsystem: "MyReader", category: "Settings")

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
            Self.log.error("保存设置失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
