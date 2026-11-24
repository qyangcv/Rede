import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        ZStack {
            if let reader = session.reader, let turner = session.turner {
                ReaderWindowContent(reader: reader, turner: turner)
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
                    .navigationTitle("阅读")
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onDisappear { session.close() }
        .onChange(of: appearsActive, initial: true) { _, active in session.setForeground(active) }
    }
}

private struct ReaderWindowContent: View {
    private enum Drawer { case toc, search, annotations, style }

    let reader: Reader
    let turner: any PageTurner
    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    @State private var noteTarget: NoteTarget?
    @State private var drawer: Drawer?
    @State private var search = ReaderSearch()
    @State private var annotationKind = Annotation.Kind.bookmark

    var body: some View {
        ReaderView(reader: reader, pages: turner.pages)
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
                    drawerButton(.toc, title: "目录", systemImage: "list.bullet")
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .navigation) {
                    drawerButton(.search, title: "在本书中查找", systemImage: "magnifyingglass", help: "在本书中查找（⌘F）")
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
                    drawerButton(.annotations, title: "标注", systemImage: "highlighter")
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    drawerButton(.style, title: "样式", systemImage: "textformat")
                        .environment(\.locale, Locale(identifier: "en"))
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
                reader.onAnnotationAction = { action in
                    session.perform(action) { id, rect in
                        noteTarget = NoteTarget(id: id, rect: rect)
                    }
                }
            }
            .ignoresSafeArea()
            .overlay {
                navigationDrawer
                    .animation(.snappy(duration: 0.22), value: drawer)
            }
            .navigationTitle(title ?? session.book?.name ?? "阅读")
            .toolbar(removing: settings.readerTitle == .hidden ? .title : nil)
            .onDisappear {
                search.cancel()
                reader.onGesture = nil
                reader.onAnnotationAction = nil
                turner.detach()
            }
            .focusedSceneValue(\.readerMenuContext, menuContext)
    }

    private var menuContext: ReaderMenuContext {
        var canTurnBack = false
        var canTurnForward = false
        if let position = reader.position, let page = session.page {
            canTurnBack = position.chapter > 0 || page.page > 0
            canTurnForward = position.chapter + 1 < reader.book.model.spine.count || page.page + 1 < page.pageCount
        }

        return ReaderMenuContext(
            canTurnBack: canTurnBack,
            canTurnForward: canTurnForward,
            hasTOC: !reader.toc.isEmpty,
            tocPresented: drawer == .toc,
            canBookmark: session.canBookmark,
            isBookmarked: session.isBookmarked,
            turn: turn,
            toggleTOC: { toggleDrawer(.toc) },
            showSearch: showSearch,
            hasSearchHits: !search.hits.isEmpty,
            stepSearch: { step in
                if let row = search.adjacent(step) { chooseHit(row) }
            },
            toggleBookmark: toggleBookmark,
            showAnnotations: showAnnotations,
            showStyle: { drawer = .style }
        )
    }

    private func showAnnotations(_ kind: Annotation.Kind) {
        annotationKind = kind
        drawer = .annotations
    }

    private func turn(_ direction: PageDirection) {
        session.turner?.turn(direction)
    }

    private func toggleBookmark() {
        session.toggleBookmark()
        reader.focus()
    }

    private var title: String? {
        switch settings.readerTitle {
        case .hidden: nil
        case .book: session.book?.name
        case .chapter: session.chapter?.path.map(\.title).joined(separator: " › ") ?? session.book?.name
        }
    }

    private func drawerButton(_ target: Drawer, title: LocalizedStringKey, systemImage: String,
                              help: LocalizedStringKey? = nil) -> some View {
        let isPresented = Binding(
            get: { drawer == target },
            set: { presented in
                if !presented {
                    closeDrawer()
                } else if target == .search {
                    showSearch()
                } else {
                    drawer = target
                }
            }
        )
        return Toggle(title, systemImage: systemImage, isOn: isPresented)
            .toggleStyle(.button)
            .help(help ?? title)
    }

    private func toggleDrawer(_ target: Drawer) {
        if drawer == target { closeDrawer() } else { drawer = target }
    }

    private func showSearch() {
        guard let book = session.book else { return }
        drawer = .search
        search.focusRequest += 1
        search.prepare(book: book, reader: reader)
    }

    private func closeDrawer() {
        drawer = nil
        reader.focus()
    }

    private func chooseHit(_ row: Int) {
        guard let index = search.index, search.hits.indices.contains(row) else { return }
        search.select(row)
        let hit = search.hits[row]
        let start = index.start(of: hit)
        drawer = nil
        reader.showSearchHit(chapter: hit.chapter, start: start, end: start + search.length)
    }

    private var navigationDrawer: some View {
        ZStack {
            if drawer != nil {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: closeDrawer)
                    .transition(.opacity)
            }

            if let drawer {
                let isTrailing = drawer == .annotations || drawer == .style
                let width: CGFloat = 300
                Group {
                    switch drawer {
                    case .toc:
                        TOCList(items: reader.toc, current: session.chapter?.id) { entry in
                            closeDrawer()
                            reader.go(to: entry)
                        }
                    case .search:
                        ReaderSearchView(search: search, reader: reader, onChoose: chooseHit, onClose: closeDrawer)
                            .transaction { $0.animation = nil }
                    case .annotations:
                        AnnotationPanel(toc: reader.toc, bookmarks: session.bookmarks, highlights: session.highlights,
                                        kind: $annotationKind, progress: session.progress(of:)) { annotation in
                            closeDrawer()
                            session.go(to: annotation)
                        } onDelete: { annotation in
                            session.deleteAnnotation(id: annotation.id)
                        }
                    case .style:
                        StylePanel(style: $settings.readerStyle, appearance: $settings.appearance)
                    }
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea(edges: .top)
                        .shadow(color: .black.opacity(0.18), radius: 18, x: isTrailing ? -6 : 6)
                }
                .geometryGroup()
                .frame(maxWidth: .infinity, alignment: isTrailing ? .trailing : .leading)
                .transition(.offset(x: isTrailing ? width : -width))
                .id(isTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
