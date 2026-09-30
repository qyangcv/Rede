import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReaderSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Book.date, order: .reverse) private var books: [Book]
    @Bindable private var settings = Settings.shared
    @State private var width: CGFloat = 0
    @State private var isImporting = false
    @State private var showSettings = false
    @State private var errors: [String] = []
    @State private var bookToDelete: Book?
    @State private var bookToEdit: Book?
    @State private var bookToShowInfo: Book?

    // iPhone 一排 3 本，iPad 卡片放大
    private var cardWidth: CGFloat { sizeClass == .regular ? 140 : 105 }

    var body: some View {
        NavigationStack {
            let grid = BookGrid.layout(width: width, cardWidth: cardWidth, minSpacing: 16)
            ScrollView {
                LazyVGrid(columns: grid.columns, spacing: 24) {
                    ForEach(books) { book in
                        BookCard(book: book)
                            .onTapGesture { open(book) }
                            .contextMenu { menu(for: book) }
                    }
                }
                .padding(.horizontal, grid.spacing)
                .padding(.vertical, 16)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("书架是空的", systemImage: "books.vertical",
                                           description: Text("点击右上角 + 导入 EPUB"))
                }
            }
            .navigationTitle("我的书库")
            .toolbar {
                ToolbarItem {
                    Button("设置", systemImage: "gearshape") { showSettings = true }
                }

                ToolbarSpacer(.fixed)

                ToolbarItemGroup {
                    AppearanceButton(appearance: $settings.appearance)
                    Button("导入", systemImage: "plus") { isImporting = true }
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
            .confirmationDialog(
                "删除：\(bookToDelete?.name ?? "") ？",
                isPresented: Binding(get: { bookToDelete != nil },
                                     set: { if !$0 { bookToDelete = nil } }),
                titleVisibility: .visible,
                presenting: bookToDelete
            ) { book in
                Button("删除", role: .destructive) { delete(book) }
            }
            .alert("操作失败", isPresented: Binding(get: { !errors.isEmpty },
                                                  set: { if !$0 { errors = [] } })) {
                Button("好") {}
            } message: {
                Text(errors.joined(separator: "\n"))
            }
            // 从"文件"App、其他 App 的"用 Rede 打开"或拖到模拟器上传入的书：导入后直接打开
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

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        Button("显示简介", systemImage: "info.circle") { bookToShowInfo = book }
        Button("编辑信息", systemImage: "pencil") { bookToEdit = book }
        ShareLink(item: EpubFile(book), preview: SharePreview(book.name)) {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        Button("删除", systemImage: "trash", role: .destructive) { bookToDelete = book }
    }

    private func save() {
        do {
            try modelContext.save()
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
