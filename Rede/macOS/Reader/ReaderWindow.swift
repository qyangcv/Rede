import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session
    @Bindable private var settings = Settings.shared

    var body: some View {
        ZStack {
            if let reader = session.reader {
                ReaderView(reader: reader, pages: session.turner?.pages, page: session.page)
                    .overlay(alignment: .top) {
                        Color.clear
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .gesture(WindowDragGesture())
                            .allowsWindowActivationEvents(true)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            TOCButton(toc: reader.toc, current: session.chapter?.id,
                                      bookmarks: session.bookmarks, progress: session.progress(of:),
                                      onSelect: reader.go(to:), onSelectBookmark: session.go(to:),
                                      onDeleteBookmark: session.deleteBookmark)
                        }
                        .sharedBackgroundVisibility(.hidden)

                        #if DEBUG
                        ToolbarItem(placement: .primaryAction) {
                            PaletteTunerButton(onDismiss: reader.focus)
                        }
                        .sharedBackgroundVisibility(.hidden)
                        #endif

                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                session.toggleBookmark()
                                reader.focus()
                            } label: {
                                Label(session.isBookmarked ? "移除书签" : "添加书签",
                                      systemImage: session.isBookmarked ? "bookmark.fill" : "bookmark")
                            }
                            .keyboardShortcut("d")
                            .disabled(!session.canBookmark)
                        }
                        .sharedBackgroundVisibility(.hidden)

                        ToolbarItem(placement: .primaryAction) {
                            StyleButton(style: $settings.readerStyle, appearance: $settings.appearance,
                                        transition: $settings.pageTransition, onDismiss: reader.focus)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    .onAppear {
                        reader.onGesture = { gesture in
                            if case .turn(let direction) = gesture { session.turner?.turn(direction) }
                        }
                    }
                    .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
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
