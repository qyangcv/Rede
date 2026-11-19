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
                    book.name = trimmed(name)
                    book.author = trimmed(author)
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty)
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
    @State private var details: BookDetails?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(BookDetails.fields(for: book, details: details)) { field in
                    Text(field.label + "：" + field.value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(width: 360)
        .task {
            details = BookDetails(book: book, in: modelContext)
        }
    }
}
