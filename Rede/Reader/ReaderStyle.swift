import SwiftUI
import os

struct FontPackage {
    // 下载物，sha256 校验的是它本身；zip 下载后解压到字体目录
    struct Asset {
        let url: URL
        let size: Int
        let sha256: String
    }

    let author: String
    let license: String
    let repository: URL
    let assets: [Asset]
    let files: [Int: String]  // 字重 → 安装后的文件名

    var size: Int { assets.reduce(0) { $0 + $1.size } }
}

enum ReaderFont: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable {
    case original, system, pingfang, lxgwWenKai, zhuqueFangsong

    var id: Self { self }

    var name: String {
        switch self {
        case .original: "默认"
        case .system: "系统"
        case .pingfang: "苹方"
        case .lxgwWenKai: "霞鹜文楷"
        case .zhuqueFangsong: "朱雀仿宋"
        }
    }

    var family: String? {
        switch self {
        case .original: nil
        case .system: "-apple-system"
        case .pingfang: "\"PingFang SC\""
        case .lxgwWenKai: "\"Rede LXGW WenKai\""
        case .zhuqueFangsong: "\"Rede Zhuque Fangsong\""
        }
    }

    var defaultWeight: Int? {
        switch self {
        case .original: nil
        case .system: 300
        case .pingfang: 300
        case .lxgwWenKai, .zhuqueFangsong: 400
        }
    }

    var weights: [Int] {
        switch self {
        case .original: []
        case .system: Array(stride(from: 200, through: 500, by: 25))
        case .pingfang: [200, 300, 400, 500]
        case .lxgwWenKai, .zhuqueFangsong: package?.files.keys.sorted() ?? []
        }
    }

    // 需要下载的字体；内置字体为 nil
    var package: FontPackage? {
        switch self {
        case .original, .system, .pingfang: nil
        case .lxgwWenKai: FontPackage(
            author: "LXGW", license: "OFL 1.1",
            repository: URL(string: "https://github.com/lxgw/LxgwWenKai")!,
            assets: [
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Light.ttf")!,
                      size: 28_267_156, sha256: "526ec70cbb0118e871d481f8179e03ff045f0e4d72d080dcca87950c4ab27cca"),
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Regular.ttf")!,
                      size: 25_575_676, sha256: "39ad71264b588165b469e35e6afb162a378dacd1f95348160240ba9038ac3009"),
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Medium.ttf")!,
                      size: 25_379_848, sha256: "d4bdeb38a39151d74d084cba5090f8cb7d20bf83eedb78c35939ae70b9f4e3f6"),
            ],
            files: [300: "LXGWWenKai-Light.ttf", 400: "LXGWWenKai-Regular.ttf", 500: "LXGWWenKai-Medium.ttf"])
        case .zhuqueFangsong: FontPackage(
            author: "TrionesType", license: "OFL 1.1",
            repository: URL(string: "https://github.com/TrionesType/zhuque")!,
            assets: [
                .init(url: URL(string: "https://github.com/TrionesType/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip")!,
                      size: 5_743_932, sha256: "bb8b661a7643d2296a72d9d10530a00949419c4e527fb61783f73c2ba1a8c062"),
            ],
            files: [400: "ZhuqueFangsong-Regular.ttf"])
        }
    }

    var directory: URL {
        AppPaths.fonts.appending(component: rawValue, directoryHint: .isDirectory)
    }

    var isAvailable: Bool { package == nil || FontStore.shared.downloaded.contains(self) }

    static var fontFaceCSS: String {
        allCases.flatMap { font in
            (font.package?.files ?? [:]).sorted { $0.key < $1.key }.map { weight, name in
                "@font-face { font-family: \(font.family ?? ""); font-weight: \(weight); src: url(\"fonts/\(font.rawValue)/\(name)\"); }"
            }
        }.joined(separator: "\n")
    }

    static func fontFile(at path: String) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "fonts",
              let font = ReaderFont(rawValue: parts[1]),
              let package = font.package,
              package.files.values.contains(parts[2]) else { return nil }
        return font.directory.appending(component: parts[2])
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
    
    var icon: String {
           switch self {
           case .system: "circle.lefthalf.filled"
           case .light: "sun.max"
           case .dark: "moon"
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
