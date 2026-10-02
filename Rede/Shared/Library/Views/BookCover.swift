import SwiftUI

struct BookCover: View {
    let book: Book
    var cornerRadius: CGFloat = 4

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { cover }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .bottomTrailing) {
                if book.file == nil { downloadBadge }
            }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
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
