import SwiftUI

struct BookCard: View {
    let book: Book
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { cover }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(book.name)
                    .font(.callout)
                    .lineLimit(1)
                    .help(book.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress = book.progress {
                    Text(progress.formatted(
                        .percent
                            .precision(.fractionLength(0...1))
                            .rounded(rule: .down)
                    ))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }
            Text(book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .padding(-8)
                .opacity(isSelected ? 1 : 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image = Image(fileURL: book.cover) {
            image
                .resizable()
                .scaledToFill()
       } else {
           Rectangle()
               .fill(.quaternary)
               .overlay {
                   Image(systemName: "book.closed")
                       .font(.largeTitle)
                       .foregroundStyle(.secondary)
               }
       }
    }
}
