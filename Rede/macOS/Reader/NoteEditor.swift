import SwiftUI

struct NoteTarget: Identifiable {
    let id: String
    let rect: CGRect
}

struct NoteEditor: View {
    let quote: String
    let hasNote: Bool
    let color: HighlightColor
    let onSave: (String) -> Void
    let onChangeColor: (HighlightColor) -> Void
    let onDelete: () -> Void

    @State private var text: String
    @State private var deleted = false
    @FocusState private var focused: Bool

    init(quote: String, note: String, color: HighlightColor,
         onSave: @escaping (String) -> Void,
         onChangeColor: @escaping (HighlightColor) -> Void,
         onDelete: @escaping () -> Void) {
        self.quote = quote
        self.hasNote = !note.isEmpty
        self.color = color
        self.onSave = onSave
        self.onChangeColor = onChangeColor
        self.onDelete = onDelete
        _text = State(initialValue: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(quote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(color.accent).frame(width: 3)
                }
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .frame(height: 140)
            Divider()
            HStack {
                HighlightColorDots(selection: color, size: 14, spacing: 8, onSelect: onChangeColor)
                Spacer()
                Button(role: .destructive) {
                    deleted = true
                    onDelete()
                } label: {
                    Label(hasNote ? "移除高亮与笔记" : "移除高亮", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { focused = true }
        .onDisappear {
            if !deleted { onSave(text) }
        }
    }
}
