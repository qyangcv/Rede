import SwiftUI

struct ReaderScreen: View {
    private static let edge = 0.3

    private enum Panel: Identifiable, Hashable {
        case toc, annotations, style
        case note(String)
        var id: Self { self }
    }

    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    @State private var chromeVisible = false
    @State private var showsJumpBar = false
    @State private var panel: Panel?
    @State private var highlightMenu: HighlightHit?
    @State private var selectionRect: CGRect?
    @State private var pendingSelectionRect: CGRect?
    @State private var annotationKind = Annotation.Kind.bookmark
    @State private var styleHeight: CGFloat?
    @State private var dismissal = Dismissal()
    @Environment(\.scenePhase) private var scenePhase

    private var jumpBarVisible: Bool {
        (chromeVisible || showsJumpBar) && (session.history.canGoBack || session.history.canGoForward)
    }

    var body: some View {
        if let reader = session.reader, let turner = session.turner {
            ReaderView(reader: reader, pages: turner.pages)
                .gesture(dismissal.gesture(for: reader.webView,
                                           shouldBegin: { panel == nil && highlightMenu == nil && selectionRect == nil && !reader.selecting },
                                           onClose: session.close))
                .overlay {
                    PageDecor(chapter: (chromeVisible || jumpBarVisible) ? nil : session.chapter, page: session.page)
                }
                .overlay {
                    turner.layer
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .background {
                    if let pages = turner.pages {
                        PageRendererHost(pages: pages)
                    }
                }
                .overlay {
                    if chromeVisible {
                        chrome.transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if jumpBarVisible {
                        historyControls
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if let hit = highlightMenu, let annotation = session.annotation(id: hit.id) {
                        HighlightActionOverlay(
                            rect: hit.rect.cgRect,
                            color: annotation.highlightColor,
                            hasNote: !annotation.note.isEmpty,
                            background: settings.readerStyle.background,
                            onSelectColor: { color in
                                if color != annotation.highlightColor {
                                    perform(.setColor(id: hit.id, color))
                                }
                            },
                            onNote: {
                                highlightMenu = nil
                                perform(.editNote(hit))
                            },
                            onDelete: {
                                highlightMenu = nil
                                perform(.delete(id: hit.id))
                            }
                        )
                        .id(hit.id)
                        .transition(.opacity)
                    } else if let rect = selectionRect {
                        SelectionActionOverlay(
                            rect: rect,
                            background: settings.readerStyle.background,
                            onHighlight: { color in
                                clearSelectionMenu()
                                perform(.highlightSelection(color))
                            },
                            onNote: {
                                clearSelectionMenu()
                                perform(.noteSelection(Settings.shared.highlightColor))
                            },
                            onCopy: {
                                clearSelectionMenu()
                                copySelection(from: reader)
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .overlay { dimmer }
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                .animation(.easeInOut(duration: 0.2), value: jumpBarVisible)
                .animation(.easeOut(duration: 0.16), value: highlightMenu)
                .animation(.easeOut(duration: 0.16), value: selectionRect != nil)
                .background {
                    settings.readerStyle.background.swatch(for: colorScheme)
                        .ignoresSafeArea()
                }
                .opacity(dismissal.isActive ? 0 : 1)
                .presentationBackground(.clear)
                .statusBarHidden(!chromeVisible)
                .sheet(item: $panel) { item in
                    sheet(item, reader: reader)
                        .presentationBackground(ChromeStyle(background: settings.readerStyle.background, level: .panel))
                        .overlay { dimmer }
                }
                .onAppear {
                    reader.onGesture = { handle($0) }
                    reader.onAnnotationAction = { perform($0) }
                    reader.onTurn = {
                        chromeVisible = false
                        showsJumpBar = false
                        highlightMenu = nil
                        clearSelectionMenu()
                        panel = nil
                    }
                    reader.webView.onTouchChange = { touching in
                        guard pendingSelectionRect != nil || selectionRect != nil else { return }
                        selectionRect = touching ? nil : pendingSelectionRect
                    }
                    reader.onSelectionRect = { [weak reader] rect in
                        pendingSelectionRect = rect
                        if rect != nil {
                            highlightMenu = nil
                        }
                        selectionRect = (reader?.webView.isTouching ?? false) ? nil : rect
                    }
                }
                .onDisappear {
                    reader.webView.onTouchChange = nil
                    reader.onSelectionRect = nil
                    UIDevice.current.isBatteryMonitoringEnabled = false
                }
                .onChange(of: session.jumpCount) {
                    if !chromeVisible, session.history.canGoBack {
                        showsJumpBar = true
                    }
                }
                .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
                .onChange(of: scenePhase, initial: true) { _, phase in session.setForeground(phase == .active) }
                .id(ObjectIdentifier(reader))
        }
    }

    private var chrome: some View {
        VStack {
            Button { dismissal.close(in: session.reader?.webView.window, onClose: session.close) } label: {
                Label("关闭", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: CGFloat(ReaderLayout.marginTop))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer()

            bottomBar
        }
        .padding(.horizontal, 20)
    }

    private var historyControls: some View {
        HStack(spacing: 4) {
            historyButton("后退", systemImage: "arrow.uturn.backward",
                          enabled: session.history.canGoBack, action: session.goBack)
            historyButton("前进", systemImage: "arrow.uturn.forward",
                          enabled: session.history.canGoForward, action: session.goForward)
        }
        .buttonStyle(.plain)
    }

    private func historyButton(_ title: String, systemImage: String,
                               enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
                .foregroundStyle(enabled ? .secondary : .quaternary)
                .frame(width: 36, height: CGFloat(ReaderLayout.marginTop))
                .contentShape(.rect)
        }
        .disabled(!enabled)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barItem("目录", systemImage: "list.bullet") { panel = .toc }
            Divider().frame(height: 20)
            barItem("标注", systemImage: "highlighter") { panel = .annotations }
            Divider().frame(height: 20)
            barItem("样式", systemImage: "textformat") {
                chromeVisible = false
                panel = .style
            }
        }
        .buttonStyle(.plain)
        .barBackground(in: .capsule, background: settings.readerStyle.background)
    }

    private func barItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .environment(\.locale, Locale(identifier: "en"))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
        }
    }

    private var dimmer: some View {
        Color.black.opacity(1 - pow(settings.brightness, 1 / 2.2))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sheet(_ item: Panel, reader: Reader) -> some View {
        switch item {
        case .toc:
            VStack(spacing: 0) {
                PanelHeader(title: "目录") { EmptyView() }
                TOCList(items: reader.toc, current: session.chapter?.id) { entry in
                    panel = nil
                    session.jump(to: entry)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .annotations:
            AnnotationSheet(
                toc: reader.toc,
                bookmarks: session.bookmarks,
                highlights: session.highlights,
                kind: $annotationKind,
                isBookmarked: session.isBookmarked,
                canBookmark: session.canBookmark,
                progress: session.progress(of:),
                onToggleBookmark: session.toggleBookmark,
                onSelect: { annotation in
                    panel = nil
                    session.jump(to: annotation)
                },
                onChangeColor: { annotation, color in
                    session.setColor(color, of: annotation)
                },
                onDelete: { annotation in
                    session.deleteAnnotation(id: annotation.id)
                }
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .note(let id):
            if let annotation = session.annotation(id: id) {
                NoteEditor(quote: annotation.text, note: annotation.note, color: annotation.highlightColor) {
                    session.setNote($0, of: annotation)
                } onChangeColor: {
                    session.setColor($0, of: annotation)
                }
                .presentationDetents([.medium, .large])
            }
        case .style:
            StyleSheet(style: $settings.readerStyle, appearance: $settings.appearance,
                       transition: $settings.pageTransition, brightness: $settings.brightness,
                       showsStatus: $settings.showsStatus)
                .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.bottom } action: { styleHeight = $0 }
                .presentationDetents([styleHeight.map { .height($0) } ?? .medium])
                .presentationBackgroundInteraction(.enabled)
        }
    }

    private func handle(_ gesture: ReaderGesture) {
        switch gesture {
        case .tap(let x):
            if highlightMenu != nil { highlightMenu = nil }
            else if chromeVisible { chromeVisible = false; showsJumpBar = false }
            else if x < Self.edge { session.turner?.turn(.prev) }
            else if x > 1 - Self.edge { session.turner?.turn(.next) }
            else if panel != nil { panel = nil; chromeVisible = true; showsJumpBar = false }
            else { chromeVisible = true; showsJumpBar = false }
        case .turn(let direction):
            highlightMenu = nil
            session.turner?.turn(direction)
        case .highlight(let hit):
            if chromeVisible { chromeVisible = false; return }
            highlightMenu = highlightMenu?.id == hit.id ? nil : hit
        }
    }

    private func perform(_ action: AnnotationAction) {
        session.perform(action) { id, _ in panel = .note(id) }
    }

    private func clearSelectionMenu() {
        pendingSelectionRect = nil
        selectionRect = nil
    }

    private func copySelection(from reader: Reader) {
        Task {
            guard let selection = await reader.takeSelection() else { return }
            UIPasteboard.general.string = selection.text
        }
    }
}

private struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
    }
}

private struct AnnotationSheet: View {
    let toc: [TOCItem]
    let bookmarks: [Annotation]
    let highlights: [Annotation]
    @Binding var kind: Annotation.Kind
    let isBookmarked: Bool
    let canBookmark: Bool
    let progress: (Annotation) -> Double?
    let onToggleBookmark: () -> Void
    let onSelect: (Annotation) -> Void
    let onChangeColor: (Annotation, HighlightColor) -> Void
    let onDelete: (Annotation) -> Void

    @State private var colorFilter: HighlightColor?

    private var filteredHighlights: [Annotation] {
        guard let colorFilter else { return highlights }
        return highlights.filter { $0.highlightColor == colorFilter }
    }

    var body: some View {
        let annotations = kind == .bookmark ? bookmarks : filteredHighlights
        VStack(spacing: 0) {
            PanelHeader(title: "标注") {
                if kind == .bookmark {
                    Button(isBookmarked ? "移除当前页书签" : "添加当前页书签",
                           systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
                           action: onToggleBookmark)
                        .font(.subheadline)
                        .disabled(!canBookmark)
                }
            }
            Picker("标注", selection: $kind) {
                Text("书签").tag(Annotation.Kind.bookmark)
                Text("高亮与笔记").tag(Annotation.Kind.highlight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if kind == .highlight, !highlights.isEmpty {
                HighlightColorFilterBar(selection: $colorFilter)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            AnnotationList(kind: kind,
                           sections: AnnotationSections(toc: toc).sections(for: annotations),
                           isFiltered: kind == .highlight && !highlights.isEmpty && colorFilter != nil,
                           progress: progress,
                           onSelect: onSelect,
                           onChangeColor: onChangeColor,
                           onDelete: onDelete)
        }
        .onChange(of: highlights.isEmpty) { _, isEmpty in
            if isEmpty { colorFilter = nil }
        }
    }
}

private struct HighlightFloatingBar<Actions: View>: View {
    let rect: CGRect
    let selection: HighlightColor?
    let background: BackgroundColor
    let onSelectColor: (HighlightColor) -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        HighlightAnchorLayout(rect: rect, topEdge: max(CGFloat(ReaderLayout.marginTop), 56)) {
            HStack(spacing: 12) {
                HighlightColorDots(selection: selection, size: 20, spacing: 10, onSelect: onSelectColor)

                Divider().frame(height: 18)

                actions
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .barBackground(in: .capsule, background: background)
        }
        .ignoresSafeArea()
    }
}

private struct OverlayActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            let icon = Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
            Group {
                if role == .destructive {
                    icon.foregroundStyle(.red)
                } else {
                    icon.foregroundStyle(.primary)
                }
            }
            .frame(width: 28, height: 32)
            .contentShape(.rect)
        }
        .accessibilityLabel(title)
    }
}

private struct HighlightActionOverlay: View {
    let rect: CGRect
    let color: HighlightColor
    let hasNote: Bool
    let background: BackgroundColor
    let onSelectColor: (HighlightColor) -> Void
    let onNote: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HighlightFloatingBar(rect: rect, selection: color, background: background, onSelectColor: onSelectColor) {
            OverlayActionButton(title: hasNote ? "查看笔记" : "添加笔记",
                                systemImage: hasNote ? "text.bubble" : "square.and.pencil",
                                action: onNote)
            OverlayActionButton(title: hasNote ? "移除高亮与笔记" : "移除高亮",
                                systemImage: "trash",
                                role: .destructive,
                                action: onDelete)
        }
    }
}

private struct SelectionActionOverlay: View {
    let rect: CGRect
    let background: BackgroundColor
    let onHighlight: (HighlightColor) -> Void
    let onNote: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HighlightFloatingBar(rect: rect, selection: nil, background: background, onSelectColor: onHighlight) {
            OverlayActionButton(title: "笔记", systemImage: "square.and.pencil", action: onNote)
            OverlayActionButton(title: "拷贝", systemImage: "doc.on.doc", action: onCopy)
        }
    }
}

private struct HighlightAnchorLayout: Layout {
    let rect: CGRect
    let topEdge: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        let halfW = size.width / 2
        let halfH = size.height / 2
        let minX = bounds.minX + halfW + 12
        let maxX = max(minX, bounds.maxX - halfW - 12)
        let x = min(max(bounds.minX + rect.midX, minX), maxX)
        let aboveY = bounds.minY + rect.minY - halfH - 10
        let belowY = bounds.minY + rect.maxY + halfH + 10
        let y = aboveY - halfH >= bounds.minY + topEdge + 8
            ? aboveY
            : min(belowY, bounds.maxY - halfH - 12)
        subview.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: ProposedViewSize(size))
    }
}

private extension View {
    func barBackground(in shape: some Shape, background: BackgroundColor) -> some View {
        self.background(ChromeStyle(background: background, level: .card), in: shape)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
