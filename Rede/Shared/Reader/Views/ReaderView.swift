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
        ZStack(alignment: .bottom) {
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
        .onChange(of: pages.map(ObjectIdentifier.init)) {
            pages?.open(style: cssVariables)
        }
        .onChange(of: cssVariables) { _, new in
            reader.apply(new)
            pages?.apply(new)
        }
    }
}

