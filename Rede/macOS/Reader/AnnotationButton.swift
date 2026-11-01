import SwiftUI

struct AnnotationButton: View {
    let toc: [TOCItem]
    let bookmarks: [Annotation]
    let highlights: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    @State private var isPresented = false
    @State private var kind = Annotation.Kind.bookmark

    var body: some View {
        Button("标注", systemImage: "highlighter") {
            isPresented.toggle()
        }
        .help("标注")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AnnotationPopover(toc: toc, bookmarks: bookmarks, highlights: highlights, kind: $kind,
                              progress: progress) { annotation in
                isPresented = false
                onSelect(annotation)
            } onDelete: { annotation in
                onDelete(annotation)
            }
        }
    }
}

private struct AnnotationPopover: View {
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
        }
        .frame(width: 300)
    }
}
