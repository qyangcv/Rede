import SwiftUI

struct ReaderScreen: View {
    // 左右两侧各占宽度的 30%，点击翻页；中间点击显示工具栏
    private static let edge = 0.3

    private enum Panel: Identifiable {
        case toc, style
        var id: Self { self }
    }

    @Environment(ReaderSession.self) private var session
    @Bindable private var settings = Settings.shared
    @State private var chromeVisible = false
    @State private var panel: Panel?
    @State private var styleHeight: CGFloat?

    var body: some View {
        if let reader = session.reader {
            // 工具栏是浮在正文上的覆盖层，不占安全区：显示或隐藏它不会改变 WebView 的尺寸和安全区，不触发 reflow
            ReaderView(reader: reader, page: session.page)
                // 章节名常驻左上角，在安全区内避开灵动岛，与正文左边缘对齐；工具栏出现时让位给关闭按钮
                .overlay(alignment: .topLeading) {
                    // 完整层级路径，放不下时截掉前面的上级，保证当前章节可见
                    if !chromeVisible, let chapter = session.chapter {
                        Text(chapter.path.map(\.title).joined(separator: " › "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .padding(.horizontal, CGFloat(ReaderLayout.gutter))
                            .padding(.top, ReaderLayout.chapterTitleTop)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if chromeVisible {
                        chrome.transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                .statusBarHidden(!chromeVisible)
                // 面板从这里弹出而不是从按钮上：工具栏的按钮样式不会传进面板
                .sheet(item: $panel) { item in
                    sheet(item, reader: reader)
                }
                .onAppear {
                    reader.onGesture = { handle($0) }
                }
                .id(ObjectIdentifier(reader))
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button("关闭", systemImage: "xmark") { session.close() }
                Spacer()
            }

            Spacer()

            HStack {
                Button("目录", systemImage: "list.bullet") { panel = .toc }
                Spacer()
                Button("样式", systemImage: "textformat") { panel = .style }
                    .environment(\.locale, Locale(identifier: "en"))
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding(.horizontal, 20)
    }

    // 面板的内边距按 Mac 气泡调过，iOS sheet 圆角大，外面再补一圈，让文字离边缘约 24pt、上边距与左边距一致
    @ViewBuilder
    private func sheet(_ item: Panel, reader: Reader) -> some View {
        switch item {
        case .toc:
            TOCList(items: reader.toc, current: session.chapter?.id) { entry in
                panel = nil
                reader.go(to: entry)
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .style:
            // 高度贴合面板内容，上方露出正文，调整时能看到实时效果
            StylePanel(style: $settings.readerStyle, appearance: $settings.appearance)
                .padding(8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { styleHeight = $0 }
                .presentationDetents([styleHeight.map { .height($0) } ?? .medium])
        }
    }

    private func handle(_ gesture: ReaderGesture) {
        guard let reader = session.reader else { return }
        switch gesture {
        case .tap(let x):
            if chromeVisible { chromeVisible = false }
            else if x < Self.edge { reader.prev() }
            else if x > 1 - Self.edge { reader.next() }
            else { chromeVisible = true }
        case .swipe(.left): reader.next()
        case .swipe(.right): reader.prev()
        }
    }
}
