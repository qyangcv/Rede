import SwiftUI

struct ReaderView: View {
    let reader: Reader
    let pages: PageRenderer?
    let page: PageInfo?

    @Environment(\.colorScheme) private var colorScheme
    @State private var safeArea = EdgeInsets()

    private var settings: Settings { .shared }

    private var cssVariables: [String: String] {
        var vars = settings.readerStyle.cssVariables(for: colorScheme)
        vars.merge(ReaderLayout.cssVariables(fontScale: settings.readerStyle.fontScale, safeArea: safeArea)) { $1 }
        #if DEBUG && os(macOS)
        PaletteTuner.shared.apply(to: &vars, scheme: colorScheme)
        #endif
        return vars
    }

    var body: some View {
        // WebView 铺满全屏，背景画到屏幕边缘，正文避开安全区交给 reader.css；页码按安全区摆放
        ZStack(alignment: .bottom) {
            // 安全区交给 CSS 变量，主 WebView 和相邻页渲染器用同一个值
            ReaderWebViewContainer(reader: reader)
                .ignoresSafeArea()
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in pages?.invalidate() }
            if let page {
                Text("\(page.page + 1) / \(page.pageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.bottom, ReaderLayout.pageNumberBottom)
            }
        }
        .onAppear {
            reader.open(style: cssVariables)
            pages?.open(style: cssVariables)
        }
        // 阅读中切换翻页方式会换一个相邻页渲染器
        .onChange(of: pages.map(ObjectIdentifier.init)) {
            pages?.open(style: cssVariables)
        }
        .onChange(of: cssVariables) { _, new in
            reader.apply(new)
            pages?.apply(new)
        }
    }
}

