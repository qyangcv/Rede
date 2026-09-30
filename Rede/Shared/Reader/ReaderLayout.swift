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
    static let marginTop = 20
    static let marginBottom = 28
    static let gutter = 24
    static let pageNumberBottom: CGFloat = 6
    #endif

    static let cssVariables = [
        "--page-margin-top": "\(marginTop)px",
        "--page-margin-bottom": "\(marginBottom)px",
        "--RS__pageGutter": "\(gutter)px",
    ]
}
