import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @State private var isImporting = false
    @State private var errors: [String] = []
    @State private var booksToDelete: [Book] = []
    @State private var selection: Set<Book.ID> = []
    @State private var anchor: Book.ID?
    @FocusState private var focused: Bool
    @State private var bookToEdit: Book?
    @State private var exportFile: EpubFile?
    @State private var bookToShowInfo: Book?
    @Environment(ReaderSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Bindable private var settings = Settings.shared

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let grid = BookGrid.layout(width: proxy.size.width, cardWidth: 150, minSpacing: 24)
                ScrollView {
                    LazyVGrid(columns: grid.columns, spacing: 28) {
                        ForEach(books) { book in
                            BookCard(book: book, isSelected: selection.contains(book.id))
                                .onTapGesture(count: 2) { open(book) }
                                .simultaneousGesture(TapGesture().onEnded { click(book) })
                                .contextMenu { menu(for: book) }
                       }
                   }
                   .padding(.horizontal, grid.spacing)
                   .padding(.vertical, 28)
                   .frame(minHeight: proxy.size.height, alignment: .top)
                   .background {
                       Color.clear
                           .contentShape(Rectangle())
                           .onTapGesture { selection = [] }
                   }
               }
               .focusable()
               .focusEffectDisabled()
               .focused($focused)
               .onCommand(#selector(NSResponder.selectAll(_:))) { selection = Set(books.map(\.id)) }
               .onExitCommand { selection = [] }
               .onDeleteCommand { booksToDelete = selectedBooks }
               .onAppear { focused = true }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView(
                        "书架是空的",
                        systemImage: "books.vertical",
                        description: Text("点击右上角按钮或拖入 EPUB")
                    )
                }
            }
            .onChange(of: books.map(\.id), initial: true) { Task { BookMerger.merge(in: modelContext) } }
            .dropDestination(for: URL.self) { urls, _ in
                let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
                importBooks(epubs)
                return !epubs.isEmpty
            }
            .navigationTitle("我的书库")
            // .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .overlay(alignment: .top) { SyncBanner() }
            .toolbar {
                if SyncMonitor.shared.hasProblem {
                    ToolbarItem { SyncAlertButton() }
                }

                ToolbarItem {
                    SettingsLink {
                        Label("设置", systemImage: "gearshape")
                    }
                    .help("设置")
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItemGroup {
                    AppearanceButton(appearance: $settings.appearance)
                    Button("导入", systemImage: "plus") { isImporting = true }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: true
            ){
                result in
                switch result {
                case .success(let urls): importBooks(urls)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            .fileExporter(
                isPresented: Binding(get: { exportFile != nil },
                                     set: { if !$0 { exportFile = nil } }),
                document: exportFile,
                contentType: .epub,
                defaultFilename: exportFile?.name
            ) { result in
                if case .failure(let error) = result { errors.append(error.localizedDescription) }
            }
            .sheet(item: $bookToEdit) { book in
                BookInfoEditor(book: book, onSave: save)
            }
            .sheet(item: $bookToShowInfo) { book in
                BookInfoView(book: book)
            }
            .confirmationDialog(
                booksToDelete.count > 1 ? "删除选中的 \(booksToDelete.count) 本书？"
                                        : "删除：\(booksToDelete.first?.name ?? "") ？",
                isPresented: Binding(get: { !booksToDelete.isEmpty },
                                     set: { if !$0 { booksToDelete = [] } }),
                presenting: booksToDelete
            ) { books in
                Button("确认", role: .destructive) { books.forEach(delete) }
            }
            .alert(
                "操作失败",
                isPresented: Binding(get: { !errors.isEmpty },
                                     set: { if !$0 {errors = [] }})
            ) {
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
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private var selectedBooks: [Book] {
        books.filter { selection.contains($0.id) }
    }

    private func click(_ book: Book) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.remove(book.id) == nil { selection.insert(book.id) }
            anchor = book.id
        } else if flags.contains(.shift), let anchor,
                  let a = books.firstIndex(where: { $0.id == anchor }),
                  let b = books.firstIndex(where: { $0.id == book.id }) {
            selection = Set(books[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [book.id]
            anchor = book.id
        }
    }

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        let targets = selection.contains(book.id) ? selectedBooks : [book]
        if targets.count > 1 {
            Button("导出 \(targets.count) 本", systemImage: "square.and.arrow.up") { export(targets.map(\.id)) }
            Button("删除 \(targets.count) 本", systemImage: "trash", role: .destructive) {
                booksToDelete = targets
            }
        } else {
            Button("打开", systemImage: "book") { open(book) }
            Button("显示简介", systemImage: "info.circle") { bookToShowInfo = book }
            Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
            Button("导出", systemImage: "square.and.arrow.up") { export([book.id]) }
            Button("删除", systemImage: "trash", role: .destructive) { booksToDelete = [book] }
        }
    }

    private func export(_ ids: [Book.ID]) {
        do {
            var files: [EpubFile] = []
            for book in try modelContext.books(ids) {
                do {
                    files.append(try EpubFile(book))
                } catch {
                    errors.append("\(book.name)：\(error.localizedDescription)")
                }
            }
            if ids.count == 1 { exportFile = files.first } else { write(files) }
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func write(_ files: [EpubFile]) {
        guard !files.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for file in files {
            do {
                try file.data.write(to: folder.appending(component: file.name))
            } catch {
                errors.append("\(file.name)：\(error.localizedDescription)")
            }
        }
    }

    private func delete(_ book: Book) {
        selection.remove(book.id)
        if session.book?.id == book.id { session.close() }
        do {
            try withAnimation {
                try BookRemover.remove(book, from: modelContext)
            }
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func open(_ book: Book) {
        do {
            try session.open(book, context: modelContext)
            openWindow(id: ReaderSession.windowID)
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

#Preview("library") {
    LibraryView()
        .modelContainer(.library)
        .environment(ReaderSession())
}
