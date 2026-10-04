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
                ContentUnavailableView("没有书签", systemImage: "bookmark", description: Text("点击上方按钮添加本页书签"))
            case .highlight:
                ContentUnavailableView("没有高亮与笔记", systemImage: "highlighter",
                                       description: Text("选中文字后在菜单中选择高亮或笔记"))
            }
        } else {
            List {
                ForEach(annotations) { annotation in
                    Button {
                        onSelect(annotation)
                    } label: {
                        AnnotationRow(annotation: annotation, isBookmark: kind == .bookmark, progress: progress(annotation))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            if annotation.note.isEmpty { onDelete(annotation) } else { pendingDelete = annotation }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .confirmDeletingNote($pendingDelete, delete: onDelete)
        }
    }
}

private struct AnnotationRow: View {
    let annotation: Annotation
    let isBookmark: Bool
    let progress: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isBookmark ? "bookmark.fill" : "highlighter")
                .foregroundStyle(isBookmark ? Color.red : Color.orange)
                .frame(width: 16)
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
