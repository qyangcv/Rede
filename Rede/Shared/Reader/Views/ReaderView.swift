import SwiftUI

struct ReaderView: View {
    let reader: Reader
    let page: PageInfo?

    @Environment(\.colorScheme) private var colorScheme

    private var settings: Settings { .shared }

    private var cssVariables: [String: String] {
        var vars = settings.readerStyle.cssVariables(for: colorScheme)
        vars.merge(ReaderLayout.cssVariables) { $1 }
        #if DEBUG && os(macOS)
        PaletteTuner.shared.apply(to: &vars, scheme: colorScheme)
        #endif
        return vars
    }

    var body: some View {
        // WebView 铺满全屏，背景画到屏幕边缘，正文避开安全区交给 reader.css；页码按安全区摆放
        ZStack(alignment: .bottom) {
            ReaderWebViewContainer(reader: reader)
                .ignoresSafeArea()
            if let page {
                Text("\(page.page + 1) / \(page.pageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.bottom, ReaderLayout.pageNumberBottom)
            }
        }
        .onAppear { reader.open(style: cssVariables) }
        .onChange(of: cssVariables) { _, new in
            reader.apply(new)
        }
    }
}

