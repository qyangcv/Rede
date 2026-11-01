import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]
    @Query private var spans: [ReadingSpan]
    @Query(sort: BookCategories.sortDescriptors) private var categories: [BookCategory]
    @State private var categorySelection: LibrarySection? = .library
    @State private var categoryToEdit: CategoryEdit?
    @State private var categoryToDelete: BookCategory?
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
        NavigationSplitView {
            sidebar
        } detail: {
            library
        }
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
            Text("分类中的书籍会保留在“我的书库”中。")
        }
    }

    private var sidebar: some View {
        List(selection: $categorySelection) {
            Label(BookCategories.libraryName, systemImage: "books.vertical")
                .tag(LibrarySection.library)
                .dropDestination(for: URL.self) { urls, _ in
                    return importEPUBs(urls, category: nil)
                }

            Section {
                ForEach(categories) { category in
                    Label(category.name, systemImage: "folder")
                        .tag(LibrarySection.category(category.id))
                        .contextMenu {
                            Button("重命名", systemImage: "pencil") {
                                categoryToEdit = CategoryEdit(category: category)
                            }
                            Button("删除分类", systemImage: "trash", role: .destructive) {
                                categoryToDelete = category
                            }
                        }
                        .dropDestination(for: URL.self) { urls, _ in
                            return importEPUBs(urls, category: category)
                        }
                }
                .onMove(perform: moveCategories)
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("分类")
                    Spacer(minLength: 8)
                    Button("新建分类", systemImage: "folder.badge.plus") { categoryToEdit = CategoryEdit() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("新建分类")
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                .padding(.trailing, 12)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 260)
    }

    private var library: some View {
        Group {
            switch settings.libraryLayout {
            case .grid:
                grid
            case .list:
                BookTable(books: sortedBooks, readingTimes: spans.readingTimes,
                          sort: $settings.librarySort, order: $settings.libraryOrder,
                          selection: $selection, open: open) { ids in
                    menu(for: visibleBooks.filter { ids.contains($0.id) })
                }
                .onDeleteCommand { booksToDelete = selectedBooks }
            }
        }
        .overlay {
            if selectedCategory == nil && visibleBooks.isEmpty {
                ContentUnavailableView(
                    "书库是空的",
                    systemImage: "books.vertical",
                    description: Text("点击右上角按钮或拖入 EPUB")
                )
            }
        }
        .onChange(of: books.map(\.id), initial: true) { Task { BookMerger.merge(in: modelContext) } }
        .dropDestination(for: URL.self) { urls, _ in
            return importEPUBs(urls, category: selectedCategory)
        }
        .navigationTitle(selectedCategory?.name ?? BookCategories.libraryName)
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

            ToolbarItem {
                Picker("陈列方式", selection: $settings.libraryLayout) {
                    ForEach(LibraryLayout.allCases) { item in
                        Label(item.name, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .help("陈列方式")
            }

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
            Button("删除书籍", role: .destructive) { books.forEach(delete) }
        } message: { _ in
            Text("书籍及其阅读进度和批注将从“我的书库”和所属分类中删除。")
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

    private var grid: some View {
        GeometryReader { proxy in
            let grid = BookGrid.layout(width: proxy.size.width, cardWidth: 150, minSpacing: 24)
            ScrollView {
                LazyVGrid(columns: grid.columns, spacing: 28) {
                    ForEach(sortedBooks) { book in
                        BookCard(book: book, isSelected: selection.contains(book.id))
                            .onTapGesture(count: 2) { open(book) }
                            .simultaneousGesture(TapGesture().onEnded { click(book) })
                            .contextMenu { menu(for: selection.contains(book.id) ? selectedBooks : [book]) }
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
            .onCommand(#selector(NSResponder.selectAll(_:))) { selection = Set(visibleBooks.map(\.id)) }
            .onExitCommand { selection = [] }
            .onDeleteCommand { booksToDelete = selectedBooks }
            .onAppear { focused = true }
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

    private var sortedBooks: [Book] {
        visibleBooks.sorted(using: BookComparator(key: settings.librarySort, order: settings.libraryOrder,
                                           readingTimes: spans.readingTimes))
    }

    private var selectedBooks: [Book] {
        visibleBooks.filter { selection.contains($0.id) }
    }

    private func click(_ book: Book) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.remove(book.id) == nil { selection.insert(book.id) }
            anchor = book.id
        } else if flags.contains(.shift), let anchor {
            let books = sortedBooks
            guard let a = books.firstIndex(where: { $0.id == anchor }),
                  let b = books.firstIndex(where: { $0.id == book.id }) else { return }
            selection = Set(books[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [book.id]
            anchor = book.id
        }
    }

    @ViewBuilder
    private func menu(for targets: [Book]) -> some View {
        if targets.count > 1 {
            categoryMenu(for: targets)
            Button("导出 \(targets.count) 本", systemImage: "square.and.arrow.up") { export(targets.map(\.id)) }
            Button("删除 \(targets.count) 本", systemImage: "trash", role: .destructive) {
                booksToDelete = targets
            }
        } else if let book = targets.first {
            Button("打开", systemImage: "book") { open(book) }
            categoryMenu(for: targets)
            Button("显示简介", systemImage: "info.circle") { bookToShowInfo = book }
            Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
            Button("导出", systemImage: "square.and.arrow.up") { export([book.id]) }
            Button("删除", systemImage: "trash", role: .destructive) { booksToDelete = [book] }
        }
    }

    private func categoryMenu(for targets: [Book]) -> some View {
        Menu("设置分类", systemImage: "folder") {
            ForEach(categories) { category in
                Toggle(category.name, isOn: Binding(
                    get: { targets.allSatisfy { $0.category?.id == category.id } },
                    set: { assign(targets, to: $0 ? category : nil) }
                ))
            }
            if targets.contains(where: { $0.category != nil }) {
                Divider()
                Button("从当前分类移除") { assign(targets, to: nil) }
            }
            Divider()
            Button("新建分类") { categoryToEdit = CategoryEdit(books: targets) }
        }
    }

    private func moveCategories(from offsets: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: offsets, toOffset: destination)
        do {
            try BookCategories.reorder(reordered, in: modelContext)
        } catch {
            errors.append(error.localizedDescription)
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
        importBooks(urls, category: selectedCategory)
    }

    private func importEPUBs(_ urls: [URL], category: BookCategory?) -> Bool {
        let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
        importBooks(epubs, category: category)
        return !epubs.isEmpty
    }

    private func importBooks(_ urls: [URL], category: BookCategory?) {
        for url in urls {
            do {
                try BookImporter.importBook(from: url, into: modelContext, category: category)
            } catch {
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
    }
}

private enum LibrarySection: Hashable {
    case library
    case category(UUID)
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
        .environment(ReaderSession())
}
