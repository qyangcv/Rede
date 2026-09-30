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
        if let reader = session.reader, let turner = session.turner {
            // 从下往上：相邻页渲染器、活的 WebView、翻页动画层；动画层不接收触摸
            // 工具栏是浮在正文上的覆盖层，不占安全区：显示或隐藏它不会改变 WebView 的尺寸和安全区，不触发 reflow
            ReaderView(reader: reader, pages: turner.pages, page: nil)
                // 章节名和页码与截图页共用 PageDecor；工具栏出现时章节名让位给关闭按钮
                .overlay {
                    PageDecor(chapter: chromeVisible ? nil : session.chapter, page: session.page)
                }
                .overlay {
                    turner.layer
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .background {
                    if let pages = turner.pages {
                        PageRendererHost(pages: pages)
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
                .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
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
            StyleForm(style: $settings.readerStyle, appearance: $settings.appearance,
                      transition: $settings.pageTransition)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, height in
                    styleHeight = height
                }
                .presentationDetents([styleHeight.map { .height($0) } ?? .medium])
        }
    }

    private func handle(_ gesture: ReaderGesture) {
        switch gesture {
        case .tap(let x):
            if chromeVisible { chromeVisible = false }
            else if x < Self.edge { session.turner?.turn(.prev) }
            else if x > 1 - Self.edge { session.turner?.turn(.next) }
            else { chromeVisible = true }
        case .turn(let direction):
            session.turner?.turn(direction)
        }
    }
}
