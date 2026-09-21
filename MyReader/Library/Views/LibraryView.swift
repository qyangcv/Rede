import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @State private var isImporting = false
    @State private var errors: [String] = []
    @State private var bookToDelete: Book?
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
                        description: Text("导入 EPUB 文件后会显示在这里")
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
            try BookImporter.importBook(from: url, into: modelContext)
        } catch {
            errors.append(error.localizedDescription)
        }
    }
    
    private func delete(_ book: Book) {
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
            try session.open(book)
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


#Preview {
    LibraryView()
        .modelContainer(for: Book.self, inMemory: true)
}
