import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session
    @Bindable private var settings = Settings.shared

    var body: some View {
        ZStack {
            if let reader = session.reader {
                ReaderView(reader: reader, page: session.page)
                    .overlay(alignment: .top) {
                        Color.clear
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .gesture(WindowDragGesture())
                            .allowsWindowActivationEvents(true)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            TOCButton(toc: reader.toc, current: session.chapter?.id, onSelect: reader.go(to:))
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
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .ignoresSafeArea()
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(session.chapter?.path.map(\.title).joined(separator: " › ") ?? session.book?.name ?? "Reader Window")
        .onDisappear { session.close() }
    }
}
