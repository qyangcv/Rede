import SwiftUI

struct ReaderView: View {
    let reader: Reader
    let page: PageInfo?
    let chapter: TOCItem?

    @Bindable private var settings = Settings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var cssVariables: [String: String] {
        var vars = settings.readerStyle.cssVariables(for: colorScheme)
        #if DEBUG
        PaletteTuner.shared.apply(to: &vars, scheme: colorScheme)
        #endif
        return vars
    }

    var body: some View {
        ReaderWebViewContainer(reader: reader)
            .overlay(alignment: .bottom) {
                if let page {
                    Text("\(page.page + 1) / \(page.pageCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TOCButton(toc: reader.toc, current: chapter?.id, onSelect: reader.go(to:))
                }
                .sharedBackgroundVisibility(.hidden)

                #if DEBUG
                ToolbarItem(placement: .primaryAction) {
                    PaletteTunerButton(onDismiss: reader.focus)
                }
                .sharedBackgroundVisibility(.hidden)
                #endif

                ToolbarItem(placement: .primaryAction) {
                    StyleButton(style: $settings.readerStyle, appearance: $settings.appearance,
                                onDismiss: reader.focus)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onAppear { reader.open(style: cssVariables) }
            .onChange(of: cssVariables) { _, new in
                reader.apply(new)
            }
    }
}

