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
        .presentationDetents([.medium])
    }
}

struct BookInfoView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var details: BookDetails?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(BookDetails.fields(for: book, details: details)) { field in
                    LabeledContent(field.label, value: field.value)
                }
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
        .presentationDetents([.medium, .large])
        .task {
            details = BookDetails(book: book, in: modelContext)
        }
    }
}
