import SwiftUI

struct NoteTarget: Identifiable {
    let id: String
    let rect: CGRect
}

struct NoteEditor: View {
    let quote: String
    let onSave: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(quote: String, note: String, onSave: @escaping (String) -> Void) {
        self.quote = quote
        self.onSave = onSave
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
                    Capsule().fill(Color.orange).frame(width: 3)
                }
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .frame(height: 140)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { focused = true }
        .onDisappear { onSave(text) }
    }
}
