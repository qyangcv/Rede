import SwiftUI

struct BookRow: View {
    let book: Book
    @Environment(\.colorScheme) private var colorScheme

    private let shape = RoundedRectangle(cornerRadius: 16)

    private var background: Color {
        colorScheme == .dark ? Color(.sRGB, red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
                             : Color(.sRGB, red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.vertical, 12)
        .background(background, in: shape)
        .contentShape(shape)
        .contentShape(.contextMenuPreview, shape)
    }
}
