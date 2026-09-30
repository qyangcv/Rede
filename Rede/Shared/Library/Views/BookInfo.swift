import SwiftUI
import SwiftData

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

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("书名") { TextField("书名", text: $name) }
                Section("作者") { TextField("作者", text: $author) }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑信息")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        book.name = trimmed(name)
                        book.author = trimmed(author)
                        onSave()
                        dismiss()
                    }
                    .disabled(trimmed(name).isEmpty)
                }
            }
        }
        .frame(minWidth: 360)
        .presentationSizing(.fitted)
        .presentationDetents([.medium])
    }
}

struct BookInfoView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: EpubMetadata?
    @State private var fileSize: Int?

    var body: some View {
        NavigationStack {
            Form {
                row("书名", book.name)
                row("作者", book.author)
                row("出版社", metadata?.publisher)
                row("出版日期", metadata?.date)
                row("ISBN", metadata?.isbn)
                row("EPUB 版本", metadata?.version)
                row("文件大小", fileSize.map { Int64($0).formatted(.byteCount(style: .file)) })
                row("字数", book.wordCount?.formatted())
                row("导入时间", book.date.formatted(date: .abbreviated, time: .shortened))
                row("最后阅读", book.lastRead?.formatted(date: .abbreviated, time: .shortened))
            }
            .formStyle(.grouped)
            .textSelection(.enabled)
            .navigationTitle("简介")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360)
        .presentationSizing(.fitted)
        .presentationDetents([.medium, .large])
        .task {
            ChapterLengthIndexer.shared.ensure(book, in: modelContext)
            let data = try? book.epubData()
            metadata = try? data.map(parseEpub)?.model.metadata
            fileSize = data?.count
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}
