import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session
    @Bindable private var settings = Settings.shared
    @State private var noteTarget: NoteTarget?
    @State private var tocPresented = false

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
                            TOCButton(isPresented: $tocPresented)
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
                            AnnotationButton(bookmarks: session.bookmarks, highlights: session.highlights,
                                             progress: session.progress(of:), onSelect: session.go(to:),
                                             onDelete: { session.deleteAnnotation(id: $0.id) })
                        }
                        .sharedBackgroundVisibility(.hidden)

                        ToolbarItem(placement: .primaryAction) {
                            StyleButton(style: $settings.readerStyle, appearance: $settings.appearance,
                                        transition: $settings.pageTransition, onDismiss: reader.focus)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    .popover(item: $noteTarget, attachmentAnchor: .rect(.rect(noteTarget?.rect ?? .zero)),
                             arrowEdge: .bottom) { target in
                        if let annotation = session.annotation(id: target.id) {
                            NoteEditor(quote: annotation.text, note: annotation.note) {
                                session.setNote($0, of: annotation)
                            }
                        }
                    }
                    .onChange(of: noteTarget == nil) { _, closed in
                        if closed { reader.focus() }
                    }
                    .onAppear {
                        reader.onGesture = { gesture in
                            switch gesture {
                            case .turn(let direction):
                                session.turner?.turn(direction)
                            case .tap, .highlight:
                                break
                            }
                        }
                        reader.onAnnotationAction = { perform($0) }
                    }
                    .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .leading) { tocDrawer }
        .animation(.snappy(duration: 0.22), value: tocPresented)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(session.chapter?.path.map(\.title).joined(separator: " › ") ?? session.book?.name ?? "Reader Window")
        .onDisappear { session.close() }
    }

    private var tocDrawer: some View {
        ZStack(alignment: .leading) {
            if tocPresented {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { tocPresented = false }
                    .transition(.opacity)
            }

            if tocPresented, let reader = session.reader {
                TOCList(items: reader.toc, current: session.chapter?.id) { entry in
                    tocPresented = false
                    reader.go(to: entry)
                    reader.focus()
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .top)
                        .shadow(color: .black.opacity(0.18), radius: 18, x: 6)
                }
                .transition(.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func perform(_ action: AnnotationAction) {
        switch action {
        case .highlightSelection:
            session.highlightSelection()
        case .noteSelection:
            session.highlightSelection { annotation, rect in noteTarget = NoteTarget(id: annotation.id, rect: rect) }
        case .editNote(let hit):
            noteTarget = NoteTarget(id: hit.id, rect: hit.rect.cgRect)
        case .delete(let id):
            session.deleteAnnotation(id: id)
        }
    }
}
