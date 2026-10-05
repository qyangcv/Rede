import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ZIPFoundation

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @Bindable private var settings = Settings.shared
    @State private var importIconMidX: CGFloat = 0
    @State private var appearanceIconMidX: CGFloat = 0
    @State private var isImporting = false
    @State private var showSettings = false
    @State private var errors: [String] = []
    @State private var booksToDelete: [Book] = []
    @State private var isSelecting = false
    @State private var selection: Set<Book.ID> = []
    @State private var bookToEdit: Book?
    @State private var bookToShowInfo: Book?
    @State private var filesToShare: [URL] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                switch settings.libraryLayout {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 0, alignment: .top)], spacing: 8) {
                        ForEach(books) { book in
                            BookCard(book: book)
                                .overlay(alignment: .topTrailing) {
                                    if isSelecting { selectionMark(for: book).padding(4) }
                                }
                                .padding(8)
                                .contentShape(Rectangle())
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 4))
                                .onTapGesture { tap(book) }
                                .contextMenu { menu(for: book) } preview: {
                                    BookCard(book: book)
                                        .padding(8)
                                        .frame(width: 140)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                case .list:
                    LazyVStack(spacing: 8) {
                        ForEach(books) { book in
                            HStack(spacing: 12) {
                                if isSelecting { selectionMark(for: book) }
                                BookRow(book: book)
                                    .contextMenu { menu(for: book) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { tap(book) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .animation(.default, value: settings.libraryLayout)
            .safeAreaBar(edge: .top) {
                if !books.isEmpty {
                    ZStack {
                        Group {
                            if isSelecting {
                                Button("删除", systemImage: "trash") { booksToDelete = selectedBooks }
                                    .buttonStyle(BarButtonStyle())
                                    .selectionAction(enabled: !selection.isEmpty)
                            } else {
                                Button("选择", systemImage: "checkmark.circle") { isSelecting = true }
                                    .buttonStyle(BarButtonStyle())
                            }
                        }
                        .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - appearanceIconMidX }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Group {
                            if isSelecting {
                                shareButton(for: Array(selection))
                                    .buttonStyle(BarButtonStyle())
                                    .selectionAction(enabled: !selection.isEmpty)
                            } else {
                                LibraryLayoutButton(layout: $settings.libraryLayout)
                            }
                        }
                        .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - importIconMidX }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onChange(of: books.map(\.id), initial: true) { _, ids in
                selection.formIntersection(ids)
                if ids.isEmpty { isSelecting = false }
                Task { BookMerger.merge(in: modelContext) }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("书架是空的", systemImage: "books.vertical",
                                           description: Text("点击右上角 + 导入 EPUB"))
                }
            }
            .navigationTitle(isSelecting ? "已选择 \(selection.count) 本" : "我的书库")
            .toolbarTitleDisplayMode(.inlineLarge)
            .containerBackground(colorScheme == .dark ? Color(.sRGB, white: 0x1A / 255)
                                                      : Color(.systemBackground),
                                 for: .navigation)
            .overlay(alignment: .top) { SyncBanner() }
            .toolbar {
                if isSelecting {
                    selectionToolbar
                } else {
                    if SyncMonitor.shared.hasProblem {
                        ToolbarItem { SyncAlertButton() }
                        ToolbarSpacer(.fixed)
                    }

                    ToolbarItem {
                        HStack(spacing: 4) {
                            Button("设置", systemImage: "gearshape") { showSettings = true }
                            AppearanceButton(appearance: $settings.appearance)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
                                    appearanceIconMidX = $0
                                }
                            Button { isImporting = true } label: {
                                Label("导入", systemImage: "plus")
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: {
                                        importIconMidX = $0
                                    }
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.epub],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importBooks(urls)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $bookToEdit) { book in
                BookInfoEditor(book: book, onSave: save)
            }
            .sheet(item: $bookToShowInfo) { book in
                BookInfoView(book: book)
            }
            .sheet(isPresented: Binding(get: { !filesToShare.isEmpty },
                                        set: { if !$0 { endSharing() } })) {
                ActivityView(items: filesToShare, onComplete: endSharing)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert(
                booksToDelete.count > 1 ? "删除选中的 \(booksToDelete.count) 本书？"
                                        : "删除：\(booksToDelete.first?.name ?? "") ？",
                isPresented: Binding(get: { !booksToDelete.isEmpty },
                                     set: { if !$0 { booksToDelete = [] } }),
                presenting: booksToDelete
            ) { books in
                Button("删除", role: .destructive) { delete(books) }
                Button("取消", role: .cancel) {}
            }
            .alert("操作失败", isPresented: Binding(get: { !errors.isEmpty },
                                                  set: { if !$0 { errors = [] } })) {
                Button("好") {}
            } message: {
                Text(errors.joined(separator: "\n"))
            }
            .onOpenURL { url in
                do {
                    open(try BookImporter.importBook(from: url, into: modelContext))
                } catch {
                    errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            .fullScreenCover(isPresented: Binding(get: { session.reader != nil },
                                                  set: { if !$0 { session.close() } })) {
                ReaderScreen()
            }
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItem {
            HStack(spacing: 4) {
                if selection.count == books.count {
                    Button("取消全选", systemImage: "checklist.checked") { selection = [] }
                } else {
                    Button("全选", systemImage: "checklist.unchecked") { selection = Set(books.map(\.id)) }
                }
                Button("取消", systemImage: "xmark") { endSelecting() }
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private func selectionMark(for book: Book) -> some View {
        let selected = selection.contains(book.id)
        return Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(selected ? .white : .secondary, selected ? Color.accentColor : .clear)
            .background(.regularMaterial, in: Circle())
    }

    private var selectedBooks: [Book] {
        books.filter { selection.contains($0.id) }
    }

    private func tap(_ book: Book) {
        guard isSelecting else { return open(book) }
        if selection.remove(book.id) == nil { selection.insert(book.id) }
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        let targets = isSelecting && selection.contains(book.id) ? selectedBooks : [book]
        if targets.count > 1 {
            shareButton(for: targets.map(\.id))
            Button("删除 \(targets.count) 本", systemImage: "trash", role: .destructive) {
                booksToDelete = targets
            }
        } else {
            Button("显示简介", systemImage: "info.circle") { bookToShowInfo = book }
            Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
            if book.file != nil { shareButton(for: [book.id]) }
            Button("删除", systemImage: "trash", role: .destructive) { booksToDelete = [book] }
        }
    }

    private func shareButton(for ids: [Book.ID]) -> some View {
        let label = ids.count > 1 ? "分享 \(ids.count) 本" : "分享"
        return Button(label, systemImage: "square.and.arrow.up") { share(ids) }
    }

    private func share(_ ids: [Book.ID]) {
        let books: [Book]
        do {
            books = try modelContext.books(ids).filter { $0.file != nil }
        } catch {
            errors.append(error.localizedDescription)
            return
        }
        guard !books.isEmpty else { return }
        let folder = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        let content = books.count > 1 ? folder.appending(component: "Rede 分享", directoryHint: .isDirectory)
                                      : folder
        do {
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            for book in books {
                try book.epubData().write(to: content.appending(component: book.exportName))
            }
            if books.count > 1 {
                let zip = folder.appending(component: content.lastPathComponent + ".zip")
                try FileManager.default.zipItem(at: content, to: zip, compressionMethod: .none)
                filesToShare = [zip]
            } else {
                filesToShare = [content.appending(component: books[0].exportName)]
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            errors.append(error.localizedDescription)
        }
    }

    private func endSharing() {
        if let folder = filesToShare.first?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: folder)
        }
        filesToShare = []
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func delete(_ books: [Book]) {
        withAnimation {
            for book in books {
                do {
                    try BookRemover.remove(book, from: modelContext)
                } catch {
                    errors.append("\(book.name)：\(error.localizedDescription)")
                }
            }
        }
        if isSelecting { endSelecting() }
    }

    private func open(_ book: Book) {
        do {
            try session.open(book, context: modelContext)
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func importBooks(_ urls: [URL]) {
        for url in urls {
            do {
                try BookImporter.importBook(from: url, into: modelContext)
            } catch {
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
    }
}

private struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private extension View {
    func selectionAction(enabled: Bool) -> some View {
        foregroundStyle(enabled ? .primary : .tertiary)
            .allowsHitTesting(enabled)
    }
}
