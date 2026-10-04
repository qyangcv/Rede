import SwiftUI

struct NoteEditor: View {
    let quote: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(quote: String, note: String, onSave: @escaping (String) -> Void) {
        self.quote = quote
        self.onSave = onSave
        _text = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(quote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.orange).frame(width: 3)
                    }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
    }
}

extension View {
    func confirmDeletingNote(_ pending: Binding<Annotation?>, delete: @escaping (Annotation) -> Void) -> some View {
        confirmationDialog("删除高亮？", isPresented: Binding(get: { pending.wrappedValue != nil },
                                                          set: { if !$0 { pending.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: pending.wrappedValue) { annotation in
            Button("删除高亮与笔记", role: .destructive) { delete(annotation) }
        } message: { _ in
            Text("这条高亮带有笔记，删除后笔记也会一并删除。")
        }
    }
}
