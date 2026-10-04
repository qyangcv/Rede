import SwiftUI

struct AnnotationList: View {
    let kind: Annotation.Kind
    let annotations: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    @State private var pendingDelete: Annotation?

    var body: some View {
        if annotations.isEmpty {
            switch kind {
            case .bookmark:
                ContentUnavailableView("没有书签", systemImage: "bookmark", description: Text("按 ⌘D 添加本页书签"))
            case .highlight:
                ContentUnavailableView("没有高亮与笔记", systemImage: "highlighter",
                                       description: Text("选中文字后右键添加高亮或笔记"))
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(annotations) { annotation in
                        AnnotationRow(annotation: annotation, isBookmark: kind == .bookmark, progress: progress(annotation)) {
                            onSelect(annotation)
                        }
                        .contextMenu {
                            Button(kind == .bookmark ? "删除书签" : "删除高亮",
                                   systemImage: "trash", role: .destructive) {
                                if annotation.note.isEmpty { onDelete(annotation) } else { pendingDelete = annotation }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .confirmDeletingNote($pendingDelete, delete: onDelete)
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
