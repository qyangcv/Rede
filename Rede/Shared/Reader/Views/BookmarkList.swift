import SwiftUI

struct BookmarkList: View {
    let bookmarks: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    var body: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView("没有书签", systemImage: "bookmark")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark, progress: progress(bookmark)) {
                            onSelect(bookmark)
                        }
                        .contextMenu {
                            Button("删除书签", systemImage: "trash", role: .destructive) {
                                onDelete(bookmark)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Annotation
    let progress: Double?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.text.isEmpty ? "插图页" : bookmark.text)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let progress {
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    }
                    Text(bookmark.created.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}
