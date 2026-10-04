import SwiftUI

struct NoteEditor: View {
    let quote: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

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
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("添加笔记…")
                                .foregroundStyle(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
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
        }
    }
}
