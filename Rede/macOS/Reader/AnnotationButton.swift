import SwiftUI

struct AnnotationPanel: View {
    let toc: [TOCItem]
    let bookmarks: [Annotation]
    let highlights: [Annotation]
    @Binding var kind: Annotation.Kind
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onChangeColor: (Annotation, HighlightColor) -> Void
    let onDelete: (Annotation) -> Void

    @State private var colorFilter: HighlightColor?

    private var filteredHighlights: [Annotation] {
        guard let colorFilter else { return highlights }
        return highlights.filter { $0.highlightColor == colorFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("标注", selection: $kind) {
                Text("书签").tag(Annotation.Kind.bookmark)
                Text("高亮与笔记").tag(Annotation.Kind.highlight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            if kind == .highlight, !highlights.isEmpty {
                HighlightColorFilterBar(selection: $colorFilter)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            AnnotationList(kind: kind,
                           sections: AnnotationSections(toc: toc).sections(for: kind == .bookmark ? bookmarks : filteredHighlights),
                           isFiltered: kind == .highlight && !highlights.isEmpty && colorFilter != nil,
                           progress: progress, onSelect: onSelect,
                           onChangeColor: onChangeColor, onDelete: onDelete)
                .id(kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: highlights.isEmpty) { _, isEmpty in
            if isEmpty { colorFilter = nil }
        }
    }
}
