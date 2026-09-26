import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @State private var isImporting = false
    @State private var errors: [String] = []
    @State private var bookToDelete: Book?
    @State private var bookToEdit: Book?
    @State private var bookToExport: Book?
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
                            BookCard(book: book)
                                .onTapGesture(count: 2) { open(book) }
                                .contextMenu {
                                    Button("打开", systemImage: "book") { open(book) }
                                    Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
                                    Button("导出", systemImage: "square.and.arrow.up") { bookToExport = book }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        bookToDelete = book
                                   }
                               }
                       }
                   }
                   .padding(.horizontal, grid.spacing)
                   .padding(.vertical, 28)
               }
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
            .confirmationDialog(
                "删除：\(bookToDelete?.name ?? "") ？",
                isPresented: Binding(get: { bookToDelete != nil },
                                     set: { if !$0 { bookToDelete = nil } }),
                presenting: bookToDelete
            ) { book in
                Button("确认", role: .destructive) { delete(book) }
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
    
    private func delete(_ book: Book) {
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
        Form {
            TextField("书名", text: $name)
            TextField("作者", text: $author)
        }
        .padding()
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    book.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
