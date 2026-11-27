import AppKit
import SwiftUI

struct ReaderWindow: View {
    let windowID: UUID
    @Environment(ReaderWindowStore.self) private var readers
    @Environment(\.appearsActive) private var appearsActive
    @State private var isFullScreen = false

    var body: some View {
        ZStack {
            if let session = readers.session(for: windowID),
               let reader = session.reader,
               let turner = session.turner {
                ReaderWindowContent(reader: reader, turner: turner)
                    .environment(session)
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
                    .navigationTitle("阅读")
            }
        }
        .toolbarBackgroundVisibility(isFullScreen ? .automatic : .hidden, for: .windowToolbar)
        .background(FullScreenToolbarBehavior(isFullScreen: $isFullScreen))
        .onDisappear { readers.close(windowID: windowID) }
        .onChange(of: appearsActive, initial: true) { _, active in
            readers.setForeground(active, for: windowID)
        }
    }
}

private struct ReaderWindowContent: View {
    private enum Drawer { case toc, search, annotations, style }

    let reader: Reader
    let turner: any PageTurner
    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    private struct PendingMarginAnchor {
        let midY: CGFloat
        let midX: Double
        let widthRatio: Double
    }

    @State private var noteTarget: NoteTarget?
    @State private var editingMarginNoteID: String?
    @State private var hoveredMarginNoteID: String?
    @State private var pendingMarginAnchors: [String: PendingMarginAnchor] = [:]
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
                    ReaderProgressBar(
                        page: page,
                        position: session.position,
                        progressRevision: session.progressRevision,
                        chapterLengths: session.book?.chapterLengths ?? [],
                        spine: reader.book.model.spine,
                        toc: reader.toc,
                        bookmarks: session.bookmarks,
                        loadEpubData: { try? session.book?.epubData() },
                        activeChapterTitle: { offset in
                            reader.tocItem(at: offset)?.entry.title
                        },
                        onJump: { target in
                            session.jump(to: target)
                        }
                    )
                }
            }
            .overlay(alignment: .bottomLeading) {
                if session.history.canGoBack || session.history.canGoForward {
                    HStack(spacing: 4) {
                        HistoryButton(
                            title: "后退",
                            systemImage: "arrow.uturn.backward",
                            enabled: session.history.canGoBack,
                            help: historyHelp("后退", entry: session.history.lastBack, shortcut: "⌘["),
                            action: session.goBack
                        )
                        HistoryButton(
                            title: "前进",
                            systemImage: "arrow.uturn.forward",
                            enabled: session.history.canGoForward,
                            help: historyHelp("前进", entry: session.history.lastForward, shortcut: "⌘]"),
                            action: session.goForward
                        )
                    }
                    .padding(.leading, CGFloat(ReaderLayout.gutter))
                    .padding(.bottom, ReaderLayout.pageNumberBottom - 4)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: session.history.canGoBack || session.history.canGoForward)
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
                    } onDelete: {
                        noteTarget = nil
                        session.deleteAnnotation(id: annotation.id)
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
                    case .highlight(let hit):
                        if marginLayout != nil {
                            pendingMarginAnchors[hit.id] = pendingAnchor(for: hit.rect.cgRect)
                            editingMarginNoteID = hit.id
                        } else {
                            noteTarget = NoteTarget(id: hit.id, rect: hit.rect.cgRect)
                        }
                    case .tap:
                        if editingMarginNoteID != nil {
                            editingMarginNoteID = nil
                            reader.focus()
                        }
                    }
                }
                reader.onSelectionChange = { selecting in
                    if selecting {
                        noteTarget = nil
                        editingMarginNoteID = nil
                    }
                }
                reader.onAnnotationAction = { action in
                    session.perform(action) { id, rect in
                        if marginLayout != nil {
                            pendingMarginAnchors[id] = pendingAnchor(for: rect)
                            editingMarginNoteID = id
                        } else {
                            noteTarget = NoteTarget(id: id, rect: rect)
                        }
                    }
                }
                reader.onCopyHighlight = { id in
                    guard let text = session.annotation(id: id)?.text else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .ignoresSafeArea()
            .overlay {
                if let layout = marginLayout {
                    MarginNotesOverlay(
                        layout: layout,
                        items: marginNotes,
                        editingID: $editingMarginNoteID,
                        hoveredID: $hoveredMarginNoteID,
                        onSave: { id, text in
                            guard let annotation = session.annotation(id: id) else { return }
                            session.setNote(text, of: annotation)
                        },
                        onDelete: { id in
                            pendingMarginAnchors.removeValue(forKey: id)
                            session.deleteAnnotation(id: id)
                        },
                        onFinishEditing: {
                            reader.focus()
                        }
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: marginLayout != nil)
            .onChange(of: editingMarginNoteID ?? hoveredMarginNoteID) { _, id in
                reader.setActiveHighlight(id)
            }
            .onChange(of: marginLayout == nil) { _, unavailable in
                if unavailable {
                    editingMarginNoteID = nil
                    hoveredMarginNoteID = nil
                    pendingMarginAnchors = [:]
                }
            }
            .onChange(of: session.position) {
                editingMarginNoteID = nil
                hoveredMarginNoteID = nil
                pendingMarginAnchors = [:]
            }
            .overlay {
                navigationDrawer
                    .animation(.snappy(duration: 0.22), value: drawer)
            }
            .navigationTitle(title ?? session.book?.name ?? "阅读")
            .toolbar(removing: settings.readerTitle == .hidden ? .title : nil)
            .onDisappear {
                search.cancel()
                reader.setActiveHighlight(nil)
                reader.onGesture = nil
                reader.onSelectionChange = nil
                reader.onAnnotationAction = nil
                reader.onCopyHighlight = nil
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
            canGoBack: session.history.canGoBack,
            canGoForward: session.history.canGoForward,
            hasTOC: !reader.toc.isEmpty,
            tocPresented: drawer == .toc,
            canBookmark: session.canBookmark,
            isBookmarked: session.isBookmarked,
            turn: turn,
            goBack: session.goBack,
            goForward: session.goForward,
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

    private var marginLayout: MarginNotesLayout? {
        guard settings.showMarginNotes,
              drawer == nil,
              (turner as? SwipePageTurner)?.slide == nil,
              let viewport = session.pageViewport else { return nil }
        return MarginNotesLayout(viewport: viewport)
    }

    private func pendingAnchor(for rect: CGRect) -> PendingMarginAnchor {
        guard let viewport = session.pageViewport else {
            return PendingMarginAnchor(midY: rect.midY, midX: 0.5, widthRatio: 1)
        }
        let contentWidth = viewport.contentRight - viewport.contentLeft
        let midX = contentWidth > 0 ? (Double(rect.midX) - viewport.contentLeft) / contentWidth : 0.5
        let widthRatio = contentWidth > 0 ? Double(rect.width) / contentWidth : 1
        return PendingMarginAnchor(midY: rect.midY, midX: midX, widthRatio: widthRatio)
    }

    private var marginNotes: [MarginNoteItem] {
        var items: [MarginNoteItem] = []
        var seen: Set<String> = []
        for anchor in session.pageHighlights {
            guard let annotation = session.annotation(id: anchor.id),
                  !annotation.note.isEmpty || editingMarginNoteID == anchor.id else { continue }
            seen.insert(anchor.id)
            items.append(MarginNoteItem(id: anchor.id, note: annotation.note,
                                        anchorMidY: CGFloat((anchor.top + anchor.bottom) / 2),
                                        midX: anchor.midX, widthRatio: anchor.widthRatio))
        }
        if let editingID = editingMarginNoteID, !seen.contains(editingID),
           let pending = pendingMarginAnchors[editingID],
           let annotation = session.annotation(id: editingID) {
            items.append(MarginNoteItem(id: editingID, note: annotation.note,
                                        anchorMidY: pending.midY,
                                        midX: pending.midX, widthRatio: pending.widthRatio))
        }
        return items.sorted { $0.anchorMidY < $1.anchorMidY }
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
        session.jump(toSearchHit: hit.chapter, start: start, end: start + search.length)
    }

    private func historyHelp(_ action: String, entry: JumpEntry?, shortcut: String) -> String {
        if let title = entry?.chapterTitle, !title.isEmpty {
            return "\(action)至「\(title)」（\(shortcut)）"
        }
        return "\(action)（\(shortcut)）"
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
                            session.jump(to: entry)
                        }
                    case .search:
                        ReaderSearchView(search: search, reader: reader, onChoose: chooseHit, onClose: closeDrawer)
                            .transaction { $0.animation = nil }
                    case .annotations:
                        AnnotationPanel(toc: reader.toc, bookmarks: session.bookmarks, highlights: session.highlights,
                                        kind: $annotationKind, progress: session.progress(of:)) { annotation in
                            closeDrawer()
                            session.jump(to: annotation)
                        } onDelete: { annotation in
                            session.deleteAnnotation(id: annotation.id)
                        }
                    case .style:
                        StylePanel(style: $settings.readerStyle, appearance: $settings.appearance,
                                   pageLayout: $settings.readerPageLayout, pageMargin: $settings.readerPageMargin)
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

private struct FullScreenToolbarBehavior: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ObserverView {
        ObserverView { fullScreen in
            if isFullScreen != fullScreen {
                isFullScreen = fullScreen
            }
        }
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private let onFullScreenChange: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var delegateProxy: FullScreenDelegateProxy?

        init(onFullScreenChange: @escaping (Bool) -> Void) {
            self.onFullScreenChange = onFullScreenChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        deinit {
            detach()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== observedWindow else { return }
            detach()
            guard let window else { return }
            observedWindow = window
            installDelegate(on: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.observedWindow === window else { return }
                self.installDelegate(on: window)
            }
            let notifications = NotificationCenter.default
            notifications.addObserver(self, selector: #selector(handleWillEnterFullScreen),
                                      name: NSWindow.willEnterFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(handleWillExitFullScreen),
                                      name: NSWindow.willExitFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(handleDidExitFullScreen),
                                      name: NSWindow.didExitFullScreenNotification, object: window)
            let fullScreen = window.styleMask.contains(.fullScreen)
            DispatchQueue.main.async { [weak self] in
                self?.onFullScreenChange(fullScreen)
            }
        }

        private func installDelegate(on window: NSWindow) {
            if let existing = delegateProxy, window.delegate === existing { return }
            let proxy = FullScreenDelegateProxy(target: window.delegate)
            delegateProxy = proxy
            window.delegate = proxy
        }

        private func detach() {
            NotificationCenter.default.removeObserver(self)
            if let window = observedWindow, let proxy = delegateProxy, window.delegate === proxy {
                window.delegate = proxy.target
            }
            delegateProxy = nil
            observedWindow = nil
        }

        @objc private func handleWillEnterFullScreen(_ notification: Notification) {
            onFullScreenChange(true)
        }

        @objc private func handleWillExitFullScreen(_ notification: Notification) {
            onFullScreenChange(false)
        }

        @objc private func handleDidExitFullScreen(_ notification: Notification) {
            onFullScreenChange(false)
        }
    }

    final class FullScreenDelegateProxy: NSObject, NSWindowDelegate {
        weak var target: (any NSWindowDelegate)?

        init(target: (any NSWindowDelegate)?) {
            self.target = target
            super.init()
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(NSWindowDelegate.window(_:willUseFullScreenPresentationOptions:)) {
                return true
            }
            return target?.responds(to: aSelector) ?? super.responds(to: aSelector)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if aSelector == #selector(NSWindowDelegate.window(_:willUseFullScreenPresentationOptions:)) {
                return self
            }
            if let target, target.responds(to: aSelector) {
                return target
            }
            return super.forwardingTarget(for: aSelector)
        }

        func window(_ window: NSWindow,
                    willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = [])
            -> NSApplication.PresentationOptions {
            let base = target?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
            return base.union([.fullScreen, .autoHideMenuBar, .autoHideToolbar])
        }
    }
}

private struct HistoryButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(enabled ? (hovering ? .primary : .secondary) : .quaternary)
                .frame(width: 24, height: 24)
                .background(enabled && hovering ? Color.primary.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
        .onHover { hovering = $0 }
    }
}
