import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    @State private var noteTarget: NoteTarget?
    @State private var tocPresented = false
    @State private var annotationsPresented = false
    @State private var annotationKind = Annotation.Kind.bookmark
    @State private var stylePresented = false

    var body: some View {
        ZStack {
            if let reader = session.reader, let turner = session.turner {
                ReaderView(reader: reader, pages: turner.pages, page: nil)
                    .background {
                        settings.readerStyle.background.swatch(for: colorScheme)
                            .ignoresSafeArea()
                    }
                    .background {
                        if let pages = turner.pages {
                            PageRendererHost(pages: pages)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .id(ObjectIdentifier(pages))
                        }
                    }
                    .overlay {
                        turner.layer
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottom) {
                        if let page = session.page {
                            Text("\(page.page + 1) / \(page.pageCount)")
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.bottom, ReaderLayout.pageNumberBottom)
                                .allowsHitTesting(false)
                        }
                    }
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

                        if settings.readerTitle == .hidden {
                            ToolbarSpacer(.flexible)
                        }

                        #if DEBUG
                        ToolbarItem(placement: .primaryAction) {
                            PaletteTunerButton(onDismiss: reader.focus)
                        }
                        .sharedBackgroundVisibility(.hidden)
                        #endif

                        ToolbarItem(placement: .primaryAction) {
                            Button(action: toggleBookmark) {
                                Label(session.isBookmarked ? "移除书签" : "添加书签",
                                      systemImage: session.isBookmarked ? "bookmark.fill" : "bookmark")
                            }
                            .disabled(!session.canBookmark)
                        }
                        .sharedBackgroundVisibility(.hidden)

                        ToolbarItem(placement: .primaryAction) {
                            AnnotationButton(isPresented: $annotationsPresented, kind: $annotationKind, toc: reader.toc,
                                             bookmarks: session.bookmarks, highlights: session.highlights,
                                             progress: session.progress(of:), onSelect: session.go(to:),
                                             onDelete: { session.deleteAnnotation(id: $0.id) })
                        }
                        .sharedBackgroundVisibility(.hidden)

                        ToolbarItem(placement: .primaryAction) {
                            StyleButton(isPresented: $stylePresented, style: $settings.readerStyle,
                                        appearance: $settings.appearance,
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
                                turn(direction)
                            case .tap, .highlight:
                                break
                            }
                        }
                        reader.onAnnotationAction = { perform($0) }
                    }
                    .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
                    .onDisappear { turner.detach() }
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .focusedSceneValue(\.readerMenuContext, menuContext)
        .ignoresSafeArea()
        .overlay(alignment: .leading) { tocDrawer }
        .animation(.snappy(duration: 0.22), value: tocPresented)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(title ?? session.book?.name ?? "阅读")
        .toolbar(removing: settings.readerTitle == .hidden ? .title : nil)
        .onDisappear { session.close() }
        .onChange(of: appearsActive, initial: true) { _, active in session.setForeground(active) }
    }

    private var menuContext: ReaderMenuContext? {
        guard let reader = session.reader else { return nil }
        var canTurnBack = false
        var canTurnForward = false
        if let position = reader.position, let page = session.page {
            canTurnBack = position.chapter > 0 || page.page > 0
            canTurnForward = position.chapter + 1 < reader.book.model.spine.count || page.page + 1 < page.pageCount
        }

        return ReaderMenuContext(
            colorScheme: colorScheme,
            canTurnBack: canTurnBack,
            canTurnForward: canTurnForward,
            hasTOC: !reader.toc.isEmpty,
            tocPresented: tocPresented,
            canBookmark: session.canBookmark,
            isBookmarked: session.isBookmarked,
            turn: turn,
            toggleTOC: { tocPresented.toggle() },
            toggleBookmark: toggleBookmark,
            showAnnotations: showAnnotations,
            showStyle: { stylePresented = true }
        )
    }

    private func showAnnotations(_ kind: Annotation.Kind) {
        annotationKind = kind
        annotationsPresented = true
    }

    private func turn(_ direction: PageDirection) {
        session.turner?.turn(direction)
    }

    private func toggleBookmark() {
        session.toggleBookmark()
        session.reader?.focus()
    }

    private var title: String? {
        switch settings.readerTitle {
        case .hidden: nil
        case .book: session.book?.name
        case .chapter: session.chapter?.path.map(\.title).joined(separator: " › ") ?? session.book?.name
        }
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
