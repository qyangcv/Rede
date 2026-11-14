import SwiftUI

struct ReaderMenuContext {
    let colorScheme: ColorScheme
    let canTurnBack: Bool
    let canTurnForward: Bool
    let hasTOC: Bool
    let tocPresented: Bool
    let canBookmark: Bool
    let isBookmarked: Bool
    let turn: (PageDirection) -> Void
    let toggleTOC: () -> Void
    let toggleBookmark: () -> Void
    let showAnnotations: (Annotation.Kind) -> Void
    let showStyle: () -> Void
}

extension FocusedValues {
    @Entry var readerMenuContext: ReaderMenuContext?
}

struct ReaderMenuCommands: View {
    @FocusedValue(\.readerMenuContext) private var context

    var body: some View {
        Button("上一页") { context?.turn(.prev) }
            .disabled(context?.canTurnBack != true)
        Button("下一页") { context?.turn(.next) }
            .disabled(context?.canTurnForward != true)
        Button(context?.tocPresented == true ? "隐藏目录" : "显示目录") { context?.toggleTOC() }
            .disabled(context?.hasTOC != true)

        Divider()

        Button(context?.isBookmarked == true ? "移除书签" : "添加书签") { context?.toggleBookmark() }
            .keyboardShortcut("d")
            .disabled(context?.canBookmark != true)
        Button("显示书签") { context?.showAnnotations(.bookmark) }
            .disabled(context == nil)
        Button("显示高亮与笔记") { context?.showAnnotations(.highlight) }
            .disabled(context == nil)
    }
}
