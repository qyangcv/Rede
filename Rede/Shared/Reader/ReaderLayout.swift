import SwiftUI

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
    static let pageNumberBottom: CGFloat = 2
    static let chapterTitleTop: CGFloat = 6
    static let bookmarkTop = 0
    #endif

    static func cssVariables(fontScale: Int, safeArea: EdgeInsets) -> [String: String] {
        var vars = [
            "--safe-top": "\(safeArea.top)px",
            "--safe-bottom": "\(safeArea.bottom)px",
            "--safe-left": "\(safeArea.leading)px",
            "--safe-right": "\(safeArea.trailing)px",
            "--page-margin-top": "\(marginTop)px",
            "--page-margin-bottom": "\(marginBottom)px",
            "--RS__pageGutter": "\(Double(gutter) * 100 / Double(fontScale))px",
        ]
        #if os(iOS)
        vars["--bookmark-display"] = "block"
        vars["--bookmark-top"] = "\(bookmarkTop)px"
        vars["--page-gutter"] = "\(gutter)px"
        #endif
        return vars
    }
}
