import SwiftUI

struct AnnotationPanel: View {
    let toc: [TOCItem]
    let bookmarks: [Annotation]
    let highlights: [Annotation]
    @Binding var kind: Annotation.Kind
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("标注", selection: $kind) {
                Text("书签").tag(Annotation.Kind.bookmark)
                Text("高亮与笔记").tag(Annotation.Kind.highlight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            AnnotationList(kind: kind,
                           sections: AnnotationSections(toc: toc).sections(for: kind == .bookmark ? bookmarks : highlights),
                           progress: progress, onSelect: onSelect, onDelete: onDelete)
                .id(kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
