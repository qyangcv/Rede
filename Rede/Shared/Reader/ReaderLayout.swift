import Foundation

// 阅读版面的平台差异：上下边距加在安全区（刘海、灵动岛、Home 条；Mac 上为 0）之外，作用于外壳页的 iframe；
// 左右留白是章节内的 --RS__pageGutter
enum ReaderLayout {
    #if os(macOS)
    static let marginTop = 60
    static let marginBottom = 50
    static let gutter = 48
    static let pageNumberBottom: CGFloat = 18
    #else
    static let marginTop = 34
    static let marginBottom = 28
    static let gutter = 28
    static let pageNumberBottom: CGFloat = 6
    static let chapterTitleTop: CGFloat = 6
    #endif

    // ReadiumCSS 用 body 的 zoom 实现字号缩放，body 的 padding（即 pageGutter）会被一并放大；
    // 这里预先除以缩放比例，让屏幕上的左右留白始终等于 gutter，不随字号变化
    static func cssVariables(fontScale: Int) -> [String: String] {
        [
            "--page-margin-top": "\(marginTop)px",
            "--page-margin-bottom": "\(marginBottom)px",
            "--RS__pageGutter": "\(Double(gutter) * 100 / Double(fontScale))px",
        ]
    }
}
