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
    @Environment(ReaderSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    
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
                        description: Text("点击右上角按钮导入 EPUB")
                    )
                }
            }
            .navigationTitle("我的书库")
            .toolbar {
                Button("导入", systemImage: "plus") { isImporting = true }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.epub],
                onCompletion: handleImport
            )
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
        }
    }
    
    private let cardWidth: CGFloat = 150
    private let minSpacing: CGFloat = 24

    private func layout(width: CGFloat) -> (columns: [GridItem], spacing: CGFloat) {
        let n = max(1, Int((width - minSpacing) / (cardWidth + minSpacing)))
        let spacing = (width - CGFloat(n) * cardWidth) / CGFloat(n + 1)
        let column = GridItem(.fixed(cardWidth), spacing: spacing)
        return (columns: Array(repeating: column, count: n), spacing: spacing)
    }
    
    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            try BookImporter.importBook(from: url, into: modelContext)
        } catch {
            errors.append(error.localizedDescription)
        }
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
            
            Text(book.name)
                .font(.callout)
                .lineLimit(2)
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

#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
}
