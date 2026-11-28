import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query private var spans: [ReadingSpan]
    @Query(sort: BookCategories.sortDescriptors) private var categories: [BookCategory]
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var categorySelection: LibrarySection? = .library
    @State private var categoryToEdit: CategoryEdit?
    @State private var categoryToDelete: BookCategory?
    @State private var isImporting = false
    @State private var importProgress: ImportProgress?
    @State private var errors: [String] = []
    @State private var booksToDelete: [Book] = []
    @State private var selection: Set<Book.ID> = []
    @State private var anchor: Book.ID?
    @State private var bookToEdit: Book?
    @State private var exportFile: EpubFile?
    @State private var bookToShowInfo: Book?
    @Environment(ReaderWindowStore.self) private var readers
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Bindable private var settings = Settings.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            library
        }
        .focusedSceneValue(\.libraryMenuContext, menuContext(for: selectedBooks))
        .onChange(of: categorySelection) {
            selection = []
            anchor = nil
        }
        .onChange(of: visibleBooks.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if let anchor, !ids.contains(anchor) { self.anchor = nil }
        }
        .onChange(of: categories.map(\.id)) {
            if case .category(let id) = categorySelection, !categories.contains(where: { $0.id == id }) {
                categorySelection = .library
            }
        }
        .task {
            restoreOpenBooks()
        }
        .sheet(item: $categoryToEdit) { edit in
            CategoryEditor(category: edit.category) { name in
                if let category = edit.category {
                    try BookCategories.rename(category, to: name, in: modelContext)
                } else {
                    let category = try BookCategories.create(named: name, books: edit.books, in: modelContext)
                    categorySelection = .category(category.id)
                }
            }
        }
        .confirmationDialog(
            "删除分类“\(categoryToDelete?.name ?? "")”？",
            isPresented: Binding(get: { categoryToDelete != nil },
                                 set: { if !$0 { categoryToDelete = nil } }),
            presenting: categoryToDelete
        ) { category in
            Button("删除分类", role: .destructive) { deleteCategory(category) }
        } message: { _ in
            Text("分类中的书籍会被保留。")
        }
    }

    private var sidebar: some View {
        LibrarySidebar(
            categories: categories.map { .init(id: $0.id, name: $0.name) },
            selection: $categorySelection,
            createCategory: createCategory,
            renameCategory: { id in
                guard let category = categories.first(where: { $0.id == id }) else { return }
                categoryToEdit = CategoryEdit(category: category)
            },
            deleteCategory: { id in
                guard let category = categories.first(where: { $0.id == id }) else { return }
                if (category.books ?? []).isEmpty {
                    deleteCategory(category)
                } else {
                    categoryToDelete = category
                }
            },
            moveCategories: moveCategories,
            importFiles: { urls, section in
                switch section {
                case .library:
                    return importFiles(urls, category: nil)
                case .category(let id):
                    guard let category = categories.first(where: { $0.id == id }) else { return false }
                    return importFiles(urls, category: category)
                }
            }
        )
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem {
                let title = columnVisibility == .detailOnly ? "显示侧边栏" : "隐藏侧边栏"
                Button(title, systemImage: "sidebar.left") {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }
                .help(title)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 260)
    }

    private var library: some View {
        Group {
            let sorting = settings.librarySorting
            let needsReadingTimes = settings.libraryLayout == .list || sorting.key == .readingTime
            let readingTimes = needsReadingTimes ? spans.readingTimes : [:]
            let sortedBooks = visibleBooks.sorted(using: BookComparator(
                key: sorting.key, order: sorting.order, readingTimes: readingTimes
            ))
            switch settings.libraryLayout {
            case .grid:
                BookGrid(books: sortedBooks, selection: $selection, anchor: $anchor, open: open) { book in
                    let targets = selection.contains(book.id) ? selectedBooks : [book]
                    LibraryBookContextMenu(selectionCount: targets.count, context: menuContext(for: targets))
                }
                .onDeleteCommand { booksToDelete = selectedBooks }
            case .list:
                BookTable(books: sortedBooks, readingTimes: readingTimes,
                          sorting: $settings.librarySorting,
                          selection: $selection, open: open) { ids in
                    let targets = visibleBooks.filter { ids.contains($0.id) }
                    LibraryBookContextMenu(selectionCount: targets.count, context: menuContext(for: targets))
                }
                .onDeleteCommand { booksToDelete = selectedBooks }
            }
        }
        .overlay {
            if selectedCategory == nil && visibleBooks.isEmpty {
                ContentUnavailableView(
                    "书库是空的",
                    systemImage: "books.vertical",
                    description: Text("点击右上角按钮或拖入电子书")
                )
            }
        }
        .onChange(of: books.map(\.id), initial: true) { Task { BookMerger.merge(in: modelContext) } }
        .dropDestination(for: URL.self) { urls, _ in
            return importFiles(urls, category: selectedCategory)
        }
        .navigationTitle(selectedCategory?.name ?? BookCategories.libraryName)
        .toolbar {
            if let progress = importProgress {
                ToolbarItem {
                    ImportProgressRing(progress: progress)
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItem {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .help("设置")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Menu {
                    Picker(LibraryDisplayCommands.layoutMenuTitle, selection: $settings.libraryLayout) {
                        ForEach(LibraryLayout.allCases) { item in
                            Label(item.name, systemImage: item.icon).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(LibraryDisplayCommands.layoutMenuTitle, systemImage: settings.libraryLayout.icon)
                }
                .menuIndicator(.hidden)
                .help(LibraryDisplayCommands.layoutMenuTitle)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItemGroup {
                AppearanceButton(appearance: $settings.appearance)
                Button("导入书籍", systemImage: "plus", action: beginImport)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: BookImporter.supportedContentTypes,
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
            Button("删除书籍", role: .destructive) { books.forEach(delete) }
        } message: { _ in
            Text("书籍和其相关数据将被删除。")
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
            Task {
                ImportProgress.begin(&importProgress, count: 1)
                defer { ImportProgress.advance(&importProgress) }
                do {
                    open(try await BookImporter.importBook(from: url, into: modelContext))
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

    private var selectedCategory: BookCategory? {
        guard case .category(let id) = categorySelection else { return nil }
        return categories.first { $0.id == id }
    }

    private var visibleBooks: [Book] {
        guard let category = selectedCategory else { return books }
        return books.filter { $0.category?.id == category.id }
    }

    private var selectedBooks: [Book] {
        visibleBooks.filter { selection.contains($0.id) }
    }

    private func menuContext(for targets: [Book]) -> LibraryMenuContext {
        let book = targets.count == 1 ? targets.first : nil
        return LibraryMenuContext(
            columnVisibility: $columnVisibility,
            beginImport: beginImport,
            createCategory: createCategory,
            open: book.map { book in { open(book) } },
            showInfo: book.map { book in { bookToShowInfo = book } },
            editInfo: book.map { book in { bookToEdit = book } },
            export: targets.isEmpty ? nil : { export(targets.map(\.id)) },
            delete: targets.isEmpty ? nil : { booksToDelete = targets },
            category: targets.isEmpty ? nil : LibraryMenuContext.Category(
                categories: categories,
                selection: BookCategories.Selection(targets),
                assign: { assign(targets, to: $0) },
                create: { categoryToEdit = CategoryEdit(books: targets) }
            )
        )
    }

    private func beginImport() {
        isImporting = true
    }

    private func createCategory() {
        categoryToEdit = CategoryEdit()
    }

    private func moveCategories(from offsets: IndexSet, to destination: Int) -> Bool {
        var reordered = categories
        reordered.move(fromOffsets: offsets, toOffset: destination)
        do {
            try BookCategories.reorder(reordered, in: modelContext)
            return true
        } catch {
            errors.append(error.localizedDescription)
            return false
        }
    }

    private func assign(_ books: [Book], to category: BookCategory?) {
        do {
            try BookCategories.assign(books, to: category, in: modelContext)
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func deleteCategory(_ category: BookCategory) {
        let id = category.id
        do {
            try BookCategories.remove(category, from: modelContext)
            if categorySelection == .category(id) { categorySelection = .library }
        } catch {
            errors.append(error.localizedDescription)
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
        if let windowID = readers.close(bookID: book.id) {
            dismissWindow(id: RedeApp.readerWindowID, value: windowID)
        }
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
            let result = try readers.open(book, context: modelContext, mode: settings.readerWindowMode)
            for id in result.dismiss {
                dismissWindow(id: RedeApp.readerWindowID, value: id)
            }
            openWindow(id: RedeApp.readerWindowID, value: result.open)
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func restoreOpenBooks() {
        let ids = readers.takeRestorableBookIDs(mode: settings.readerWindowMode)
        guard !ids.isEmpty, let fetched = try? modelContext.books(ids) else { return }
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in ids {
            guard let book = byID[id],
                  let result = try? readers.open(book, context: modelContext, mode: settings.readerWindowMode)
            else { continue }
            openWindow(id: RedeApp.readerWindowID, value: result.open)
        }
    }

    private func importBooks(_ urls: [URL]) {
        importBooks(urls, category: selectedCategory)
    }

    private func importFiles(_ urls: [URL], category: BookCategory?) -> Bool {
        let supported = urls.filter(BookImporter.supports)
        importBooks(supported, category: category)
        return !supported.isEmpty
    }

    private func importBooks(_ urls: [URL], category: BookCategory?) {
        guard !urls.isEmpty else { return }
        ImportProgress.begin(&importProgress, count: urls.count)
        Task {
            let newErrors = await BookImporter.importBooks(from: urls, into: modelContext, category: category) {
                ImportProgress.advance(&importProgress)
            }
            errors += newErrors
        }
    }
}

private struct CategoryEdit: Identifiable {
    let id = UUID()
    var category: BookCategory?
    var books: [Book] = []
}

private struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var name: String
    @State private var error: String?
    let category: BookCategory?
    let save: (String) throws -> Void

    init(category: BookCategory?, save: @escaping (String) throws -> Void) {
        self.category = category
        self.save = save
        _name = State(initialValue: category?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(category == nil ? "新建分类" : "重命名分类")
                .font(.headline)
            TextField("分类名称", text: $name)
                .focused($isFocused)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(category == nil ? "创建" : "保存") {
                    do {
                        try save(name)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { isFocused = true }
    }
}

#Preview("library") {
    LibraryView()
        .modelContainer(.library)
        .environment(ReaderWindowStore())
}
