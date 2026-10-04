import SwiftUI

struct AnnotationList: View {
    let kind: Annotation.Kind
    let annotations: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if annotations.isEmpty {
            switch kind {
            case .bookmark:
                EmptyState(title: "没有书签", systemImage: "bookmark", description: "按 ⌘D 添加本页书签")
            case .highlight:
                EmptyState(title: "没有高亮与笔记", systemImage: "highlighter", description: "选中文字后右键添加高亮或笔记")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(annotations) { annotation in
                        AnnotationRow(annotation: annotation, isBookmark: kind == .bookmark, progress: progress(annotation)) {
                            onSelect(annotation)
                        }
                        .contextMenu {
                            Button(kind == .bookmark ? "移除书签" : annotation.note.isEmpty ? "移除高亮" : "移除高亮与笔记",
                                   systemImage: "trash", role: .destructive) {
                                onDelete(annotation)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 460))
        }
    }
}

private struct AnnotationRow: View {
    let annotation: Annotation
    let isBookmark: Bool
    let progress: Double?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isBookmark ? "bookmark.fill" : "highlighter")
                    .foregroundStyle(isBookmark ? Color.red : Color.orange)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(annotation.text.isEmpty ? (isBookmark ? "插图页" : "插图") : annotation.text)
                        .lineLimit(isBookmark ? 2 : 4)
                    if !annotation.note.isEmpty {
                        Text(annotation.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.leading, 8)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.orange).frame(width: 2)
                            }
                    }
                    HStack(spacing: 8) {
                        if let progress {
                            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        }
                        Text(annotation.created.formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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

private struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Text(title)
                .font(.title3.bold())
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .padding(.vertical, 32)
    }
}
