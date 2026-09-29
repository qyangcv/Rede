import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// 临时书库：只负责导入和打开，完整的书库在目标 3 实现
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReaderSession.self) private var session
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @State private var isImporting = false
    @State private var errors: [String] = []

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button { open(book) } label: {
                    VStack(alignment: .leading) {
                        Text(book.name)
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("书架是空的", systemImage: "books.vertical",
                                           description: Text("点击右上角按钮导入 EPUB"))
                }
            }
            .navigationTitle("我的书库")
            .toolbar {
                Button("导入", systemImage: "plus") { isImporting = true }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.epub],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importBooks(urls)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            .alert("操作失败", isPresented: Binding(get: { !errors.isEmpty },
                                                  set: { if !$0 { errors = [] } })) {
                Button("好") {}
            } message: {
                Text(errors.joined(separator: "\n"))
            }
            // 从"文件"App、其他 App 的"用 Rede 打开"或拖到模拟器上传入的书
            .onOpenURL { url in importBooks([url]) }
            .fullScreenCover(isPresented: Binding(get: { session.reader != nil },
                                                  set: { if !$0 { session.close() } })) {
                ReaderScreen()
            }
        }
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
