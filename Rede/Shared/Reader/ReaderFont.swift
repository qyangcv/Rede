import Foundation

struct FontPackage {
    struct Asset {
        let url: URL
        let size: Int
        let sha256: String
    }

    struct Face {
        let file: String
        let weights: ClosedRange<Int>
    }

    let author: String
    let license: String
    let repository: URL
    let assets: [Asset]
    let faces: [Face]

    static let revisionFile = "revision"

    var size: Int { assets.reduce(0) { $0 + $1.size } }

    var revision: String { assets.map(\.sha256).joined(separator: "\n") }

    var weights: [Int] {
        Set(faces.flatMap { stride(from: $0.weights.lowerBound, through: $0.weights.upperBound, by: 25) }).sorted()
    }
}

enum ReaderFont: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable {
    case original, system, pingfang, songti, hiragino, lxgwWenKai, zhuqueFangsong, sourceHanSans, sourceHanSerif

    var id: Self { self }

    var name: String {
        switch self {
        case .original: "默认"
        case .system: "系统"
        case .pingfang: "苹方"
        case .songti: "宋体"
        case .hiragino: "冬青黑体"
        case .lxgwWenKai: "霞鹜文楷"
        case .zhuqueFangsong: "朱雀仿宋"
        case .sourceHanSans: "思源黑体"
        case .sourceHanSerif: "思源宋体"
        }
    }

    var family: String? {
        switch self {
        case .original: nil
        case .system: "-apple-system"
        case .pingfang: "\"PingFang SC\""
        case .songti: "\"Songti SC\""
        case .hiragino: "\"Hiragino Sans GB\""
        case .lxgwWenKai: "\"Rede LXGW WenKai\""
        case .zhuqueFangsong: "\"Rede Zhuque Fangsong\""
        case .sourceHanSans: "\"Rede Source Han Sans\""
        case .sourceHanSerif: "\"Rede Source Han Serif\""
        }
    }

    #if os(macOS)
    var defaultWeight: Int? {
        switch self {
        case .original: nil
        case .system: 325
        case .pingfang: 300
        case .songti: 400
        case .hiragino: 400
        case .lxgwWenKai: 300
        case .zhuqueFangsong: 400
        case .sourceHanSans: 300
        case .sourceHanSerif: 375
        }
    }

    var weights: [Int] {
        switch self {
        case .original: []
        case .system: Array(stride(from: 175, through: 500, by: 25))
        case .pingfang: [100, 200, 300, 400, 500]
        case .songti: [300, 400, 700, 900]
        case .hiragino: [400, 600]
        case .sourceHanSans: Array(stride(from: 250, through: 500, by: 25))
        case .sourceHanSerif: Array(stride(from: 250, through: 600, by: 25))
        case .lxgwWenKai, .zhuqueFangsong: package?.weights ?? []
        }
    }
    #else
    var defaultWeight: Int? {
        weights.isEmpty ? nil : weights[weights.count / 2]
    }

    var weights: [Int] {
        switch self {
        case .original, .songti, .hiragino: []
        case .system, .sourceHanSans: [300, 350, 400, 450, 550]
        case .sourceHanSerif: [350, 400, 450, 500, 600]
        case .pingfang, .lxgwWenKai: [300, 400, 500]
        case .zhuqueFangsong: [400]
        }
    }
    #endif

    var package: FontPackage? {
        switch self {
        case .original, .system, .pingfang, .songti, .hiragino: nil
        case .lxgwWenKai: FontPackage(
            author: "LXGW", license: "OFL 1.1",
            repository: URL(string: "https://github.com/lxgw/LxgwWenKai")!,
            assets: [
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Light.ttf")!,
                    size: 28_625_516, sha256: "9a50e3f0f51fad60d68152d5191bce1a495bfc4b9ceb1cee24833835511d1dca"),
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf")!,
                    size: 25_928_940, sha256: "2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"),
                .init(url: URL(string: "https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf")!,
                    size: 25_800_076, sha256: "f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"),
            ],
            faces: [.init(file: "LXGWWenKai-Light.ttf", weights: 300...300),
                    .init(file: "LXGWWenKai-Regular.ttf", weights: 400...400),
                    .init(file: "LXGWWenKai-Medium.ttf", weights: 500...500)])
        case .zhuqueFangsong: FontPackage(
            author: "TrionesType", license: "OFL 1.1",
            repository: URL(string: "https://github.com/TrionesType/zhuque")!,
            assets: [
                .init(url: URL(string: "https://github.com/TrionesType/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip")!,
                      size: 5_743_932, sha256: "bb8b661a7643d2296a72d9d10530a00949419c4e527fb61783f73c2ba1a8c062"),
            ],
            faces: [.init(file: "ZhuqueFangsong-Regular.ttf", weights: 400...400)])
        case .sourceHanSans: FontPackage(
            author: "Adobe", license: "OFL 1.1",
            repository: URL(string: "https://github.com/adobe-fonts/source-han-sans")!,
            assets: [
                .init(url: URL(string: "https://raw.githubusercontent.com/adobe-fonts/source-han-sans/6c709ca72d3d7c46ab42ebecc1a26e7d69595a37/Variable/WOFF2/OTF/Subset/SourceHanSansCN-VF.otf.woff2")!,
                      size: 7_995_716, sha256: "7087698d52240614659957608d8c4ad446759aee3208409dc9f566412e7af8f4"),
            ],
            faces: [.init(file: "SourceHanSansCN-VF.otf.woff2", weights: 250...900)])
        case .sourceHanSerif: FontPackage(
            author: "Adobe", license: "OFL 1.1",
            repository: URL(string: "https://github.com/adobe-fonts/source-han-serif")!,
            assets: [
                .init(url: URL(string: "https://raw.githubusercontent.com/adobe-fonts/source-han-serif/7889f11bf31170b5d092a083b357c8c8130f89e0/Variable/WOFF2/OTF/Subset/SourceHanSerifCN-VF.otf.woff2")!,
                      size: 10_421_244, sha256: "808cb3203bb9cdd6b166a8a656a0c7608a7dc2a31c41c2cd0374550cae445471"),
            ],
            faces: [.init(file: "SourceHanSerifCN-VF.otf.woff2", weights: 250...900)])
        }
    }

    var directory: URL {
        AppPaths.fonts.appending(component: rawValue, directoryHint: .isDirectory)
    }

    var installedRevision: String? {
        try? String(contentsOf: directory.appending(component: FontPackage.revisionFile), encoding: .utf8)
    }

    var isBuiltin: Bool { package == nil }

    #if os(macOS)
    private static let preinstalled: Set<ReaderFont> = [.original, .system, .pingfang, .songti, .hiragino]
    #else
    private static let preinstalled: Set<ReaderFont> = [.original, .system, .pingfang]
    #endif

    var isAvailable: Bool {
        isBuiltin ? Self.preinstalled.contains(self) : FontStore.shared.downloaded.contains(self)
    }

    static var fontFaceCSS: String {
        allCases.flatMap { font in
            (font.package?.faces ?? []).map { face in
                "@font-face { font-family: \(font.family ?? ""); font-weight: \(face.weights.lowerBound) \(face.weights.upperBound); src: url(\"fonts/\(font.rawValue)/\(face.file)\"); }"
            }
        }.joined(separator: "\n")
    }

    static func fontFile(at path: String) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "fonts",
              let font = ReaderFont(rawValue: parts[1]),
              let package = font.package,
              package.faces.contains(where: { $0.file == parts[2] }) else { return nil }
        return font.directory.appending(component: parts[2])
    }
}
