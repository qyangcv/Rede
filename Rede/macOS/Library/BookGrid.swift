import SwiftUI

struct BookGrid<Menu: View>: View {
    let books: [Book]
    @Binding var selection: Set<Book.ID>
    @Binding var anchor: Book.ID?
    let open: (Book) -> Void
    @ViewBuilder var menu: (Book) -> Menu
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            let grid = Self.layout(width: proxy.size.width, cardWidth: 150, minSpacing: 24)
            ScrollView {
                LazyVGrid(columns: grid.columns, spacing: 28) {
                    ForEach(books) { book in
                        BookCard(book: book, isSelected: selection.contains(book.id))
                            .onTapGesture(count: 2) { open(book) }
                            .simultaneousGesture(TapGesture().onEnded { click(book) })
                            .contextMenu { menu(book) }
                    }
                }
                .padding(.horizontal, grid.spacing)
                .padding(.vertical, 28)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { selection = [] }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onCommand(#selector(NSResponder.selectAll(_:))) { selection = Set(books.map(\.id)) }
            .onExitCommand { selection = [] }
            .onAppear { focused = true }
        }
    }

    private func click(_ book: Book) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.remove(book.id) == nil { selection.insert(book.id) }
            anchor = book.id
        } else if flags.contains(.shift), let anchor {
            guard let a = books.firstIndex(where: { $0.id == anchor }),
                  let b = books.firstIndex(where: { $0.id == book.id }) else { return }
            selection = Set(books[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [book.id]
            anchor = book.id
        }
    }

    private static func layout(width: CGFloat, cardWidth: CGFloat,
                               minSpacing: CGFloat) -> (columns: [GridItem], spacing: CGFloat) {
        let n = max(1, Int((width - minSpacing) / (cardWidth + minSpacing)))
        let spacing = (width - CGFloat(n) * cardWidth) / CGFloat(n + 1)
        let column = GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top)
        return (columns: Array(repeating: column, count: n), spacing: spacing)
    }
}
