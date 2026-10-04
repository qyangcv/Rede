import SwiftUI

struct AnnotationButton: View {
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
            VStack(spacing: 0) {
                Picker("标注", selection: $kind) {
                    Text("书签").tag(Annotation.Kind.bookmark)
                    Text("高亮与笔记").tag(Annotation.Kind.highlight)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)

                Divider()

                AnnotationList(kind: kind, annotations: kind == .bookmark ? bookmarks : highlights,
                               progress: progress) { annotation in
                    isPresented = false
                    onSelect(annotation)
                } onDelete: { annotation in
                    onDelete(annotation)
                }
            }
            .frame(width: 300)
        }
    }
}
