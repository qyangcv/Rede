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
    @State private var bookToExport: Book?
    @State private var bookToShowInfo: Book?
    @Environment(ReaderSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Bindable private var settings = Settings.shared
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let grid = layout(width: proxy.size.width)
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
            .dropDestination(for: URL.self) { urls, _ in
                let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
                importBooks(epubs)
                return !epubs.isEmpty
            }
            .navigationTitle("我的书库")
            .toolbar {
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
                isPresented: Binding(get: { bookToExport != nil },
                                     set: { if !$0 { bookToExport = nil } }),
                document: bookToExport.map { EpubFile(url: $0.url) },
                contentType: .epub,
                defaultFilename: bookToExport?.exportName
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
    
    private let cardWidth: CGFloat = 150
    private let minSpacing: CGFloat = 24

    private func layout(width: CGFloat) -> (columns: [GridItem], spacing: CGFloat) {
        let n = max(1, Int((width - minSpacing) / (cardWidth + minSpacing)))
        let spacing = (width - CGFloat(n) * cardWidth) / CGFloat(n + 1)
        let column = GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top)
        return (columns: Array(repeating: column, count: n), spacing: spacing)
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
            Button("导出 \(targets.count) 本", systemImage: "square.and.arrow.up") { export(targets) }
            Button("删除 \(targets.count) 本", systemImage: "trash", role: .destructive) {
                booksToDelete = targets
            }
        } else {
            Button("打开", systemImage: "book") { open(book) }
            Button("显示简介", systemImage: "info.circle") { bookToShowInfo = book }
            Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
            Button("导出", systemImage: "square.and.arrow.up") { bookToExport = book }
            Button("删除", systemImage: "trash", role: .destructive) { booksToDelete = [book] }
        }
    }

    private func export(_ books: [Book]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for book in books {
            do {
                try FileManager.default.copyItem(at: book.url, to: folder.appending(component: book.exportName))
            } catch {
                errors.append("\(book.name)：\(error.localizedDescription)")
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
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                try BookImporter.importBook(from: url, into: modelContext)
            } catch {
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
    }
}

struct AppearanceButton: View {
    @Binding var appearance: Appearance

    var body: some View {
        Menu {
            Picker("外观", selection: $appearance) {
                ForEach(Appearance.allCases) { item in
                    Label(item.name, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("外观", systemImage: appearance.icon)
        }
        .menuIndicator(.hidden)
        .help("外观")
    }
}

struct BookCard: View {
    let book: Book
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { cover }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(book.name)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress = book.progress {
                    Text(progress.formatted(
                        .percent
                            .precision(.fractionLength(0...1))
                            .rounded(rule: .down)
                    ))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }
            Text(book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .padding(-8)
                .opacity(isSelected ? 1 : 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image = NSImage(contentsOf: book.cover) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
       } else {
           Rectangle()
               .fill(.quaternary)
               .overlay {
                   Image(systemName: "book.closed")
                       .font(.largeTitle)
                       .foregroundStyle(.secondary)
               }
       }
    }
}

struct BookInfoEditor: View {
    let book: Book
    let onSave: () -> Void
    
    @State private var name: String
    @State private var author: String
    @Environment(\.dismiss) private var dismiss
    
    init(book: Book, onSave: @escaping () -> Void) {
        self.book = book
        self.onSave = onSave
        _name = State(initialValue: book.name)
        _author = State(initialValue: book.author)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Form {
                TextField("书名", text: $name)
                TextField("作者", text: $author)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    book.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

struct BookInfoView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: EpubMetadata?
    @State private var fileSize: Int?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                row("书名", book.name)
                row("作者", book.author)
                row("出版社", metadata?.publisher)
                row("出版日期", metadata?.date)
                row("ISBN", metadata?.isbn)
                row("EPUB 版本", metadata?.version)
                row("文件大小", fileSize.map { Int64($0).formatted(.byteCount(style: .file)) })
                row("总字数", book.wordCount?.formatted())
                row("导入时间", book.date.formatted(date: .abbreviated, time: .shortened))
                row("最后阅读", book.lastRead?.formatted(date: .abbreviated, time: .shortened))
            }
            .textSelection(.enabled)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(width: 360)
        .task {
            ChapterLengthIndexer.shared.ensure(book, in: modelContext)
            metadata = try? parseEpub(at: book.url).model.metadata
            fileSize = try? book.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(label + "：" + value)
        }
    }
}

struct EpubFile: FileDocument {
    static let readableContentTypes: [UTType] = [.epub]
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}


#Preview("library") {
    LibraryView()
        .modelContainer(.localLibrary)
        .environment(ReaderSession())
}
