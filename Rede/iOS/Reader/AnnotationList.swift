import SwiftUI

struct AnnotationList: View {
    let kind: Annotation.Kind
    let sections: [AnnotationSections.Section]
    var isFiltered = false
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onChangeColor: (Annotation, HighlightColor) -> Void
    let onDelete: (Annotation) -> Void

    var body: some View {
        if sections.isEmpty {
            switch kind {
            case .bookmark:
                ContentUnavailableView("没有书签", systemImage: "bookmark", description: Text("点击按钮添加当前页书签"))
            case .highlight:
                if isFiltered {
                    ContentUnavailableView("没有该颜色的高亮", systemImage: "highlighter",
                                           description: Text("切换其他颜色或选择「全部」查看"))
                } else {
                    ContentUnavailableView("没有高亮与笔记", systemImage: "highlighter",
                                           description: Text("选中文字后在菜单中选择高亮或笔记"))
                }
            }
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.annotations) { annotation in
                            Button {
                                onSelect(annotation)
                            } label: {
                                AnnotationRow(annotation: annotation, isBookmark: kind == .bookmark, progress: progress(annotation))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                if kind == .highlight {
                                    Menu("更改颜色", systemImage: "paintpalette") {
                                        ForEach(HighlightColor.allCases) { color in
                                            Button {
                                                onChangeColor(annotation, color)
                                            } label: {
                                                Label(color.name,
                                                      systemImage: color == annotation.highlightColor ? "checkmark" : "circle.fill")
                                            }
                                        }
                                    }
                                    Divider()
                                }
                                Button(kind == .bookmark ? "移除书签" : annotation.note.isEmpty ? "移除高亮" : "移除高亮与笔记",
                                       systemImage: "trash", role: .destructive) {
                                    onDelete(annotation)
                                }
                            }
                            .swipeActions {
                                Button("移除", systemImage: "trash", role: .destructive) {
                                    onDelete(annotation)
                                }
                            }
                        }
                    } header: {
                        if let title = section.title { Text(title) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct AnnotationRow: View {
    let annotation: Annotation
    let isBookmark: Bool
    let progress: Double?

    var body: some View {
        let accent = annotation.highlightColor.accent
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isBookmark ? "bookmark.fill" : "highlighter")
                .foregroundStyle(isBookmark ? Color.red : accent)
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
                            Capsule().fill(accent).frame(width: 2)
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
