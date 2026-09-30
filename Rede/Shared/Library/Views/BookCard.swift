import SwiftUI

struct BookCard: View {
    let book: Book
    var isSelected = false

    // 同名字号在 iOS 上比 Mac 大一截，iPhone 的卡片又更窄，按平台取字号
    #if os(macOS)
    private static let titleFont = Font.callout
    private static let detailFont = Font.caption
    #else
    private static let titleFont = Font.footnote
    private static let detailFont = Font.caption2
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { cover }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomTrailing) {
                    if book.file == nil { downloadBadge }
                }
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            
            Text(book.name)
                .font(Self.titleFont)
                .lineLimit(1)
                .help(book.name)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(book.author)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress = book.progress {
                    Text(progress.formatted(
                        .percent
                            .precision(.fractionLength(0...1))
                            .rounded(rule: .down)
                    ))
                    .monospacedDigit()
                    .fixedSize()
                }
            }
            .font(Self.detailFont)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .padding(-8)
                .opacity(isSelected ? 1 : 0)
        }
    }

    // EPUB 本体还没从 iCloud 下载下来：书的信息和文件是两条记录，文件可能晚到
    private var downloadBadge: some View {
        Image(systemName: "icloud.and.arrow.down")
            .font(.caption)
            .padding(5)
            .background(.regularMaterial, in: Circle())
            .padding(4)
            .help("正在从 iCloud 下载")
    }

    @ViewBuilder
    private var cover: some View {
        if let image = book.cover.flatMap(Image.init(data:)) {
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
