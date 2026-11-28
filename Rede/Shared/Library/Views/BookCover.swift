import SwiftUI

struct BookCover: View {
    let book: Book
    var cornerRadius: CGFloat = 4
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { cover }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomTrailing) {
                if book.file == nil { downloadBadge }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.13), radius: 3, y: 2)
    }

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
            placeholder
        }
    }

    private var placeholder: some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return GeometryReader { proxy in
            let scale = proxy.size.width / 150
            let badgeShape = RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
            LinearGradient(
                colors: [
                    Color(white: isDark ? 0.175 : 0.955),
                    Color(white: isDark ? 0.155 : 0.935)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                badgeShape
                    .fill(isDark ? Color(white: 0.235) : Color.white.opacity(0.88))
                    .frame(width: 44 * scale, height: 44 * scale)
                    .shadow(color: .black.opacity(isDark ? 0.25 : 0.045), radius: 3 * scale, y: 1.5 * scale)
                    .overlay {
                        badgeShape
                            .strokeBorder(
                                isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05),
                                lineWidth: 0.6
                            )
                    }
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: 18 * scale, weight: .light))
                            .foregroundStyle(isDark ? Color.white.opacity(0.36) : Color.black.opacity(0.28))
                    }
            }
            .overlay {
                shape.strokeBorder(
                    isDark ? Color.white.opacity(0.095) : Color.black.opacity(0.075),
                    lineWidth: 0.65
                )
            }
            .overlay {
                shape.inset(by: 0.65)
                    .strokeBorder(
                        isDark ? Color.white.opacity(0.035) : Color.white.opacity(0.72),
                        lineWidth: 0.55
                    )
            }
        }
    }
}
