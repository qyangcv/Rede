import SwiftUI

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
    case white, paper, sepia

    var id: Self { self }

    var name: String {
        switch self {
        case .white: "白色"
        case .paper: "默认"
        case .sepia: "米黄"
        }
    }

    var color: String {
        switch self {
        case .white: "#ffffff"
        case .paper: "#e5e5e5"
        case .sepia: "#f4ecd8"
        }
    }

    var swatch: Color { Color(hex: color) }
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
    var fontSize: Int
    var lineSpacing: Spacing
    var paraSpacing: Spacing
    var background: BackgroundColor

    static let fontSizeRange = 12...32
    static let `default` = ReaderStyle(fontSize: 18, lineSpacing: .standard,
                                      paraSpacing: .standard, background: .paper)

    var cssVariables: [String: String] {
        [
            "--font-size": "\(fontSize)px",
            "--line-height": "\(lineSpacing.lineHeight)",
            "--para-spacing": "\(paraSpacing.paraSpacing)em",
            "--bg": background.color,
        ]
    }
}

extension ReaderStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case fontSize, lineSpacing, paraSpacing, background
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReaderStyle.default
        fontSize = try container.decodeIfPresent(Int.self, forKey: .fontSize) ?? fallback.fontSize
        lineSpacing = try container.decodeIfPresent(Spacing.self, forKey: .lineSpacing) ?? fallback.lineSpacing
        paraSpacing = try container.decodeIfPresent(Spacing.self, forKey: .paraSpacing) ?? fallback.paraSpacing
        background = try container.decodeIfPresent(BackgroundColor.self, forKey: .background) ?? fallback.background
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(lineSpacing, forKey: .lineSpacing)
        try container.encode(paraSpacing, forKey: .paraSpacing)
        try container.encode(background, forKey: .background)
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
