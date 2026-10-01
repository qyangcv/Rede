import SwiftUI

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            BookCover(book: book, cornerRadius: 3)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                // 列表模式就是为了让长书名显示完整，给两行
                Text(book.name)
                    .font(.body)
                    .lineLimit(2)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
