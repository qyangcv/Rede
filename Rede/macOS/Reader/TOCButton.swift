import SwiftUI

enum NavigatorTab: CaseIterable, Identifiable {
    case toc, bookmarks, highlights

    var id: Self { self }

    var name: String {
        switch self {
        case .toc: "目录"
        case .bookmarks: "书签"
        case .highlights: "高亮与笔记"
        }
    }
}

struct TOCButton: View {
    let toc: [TOCItem]
    let current: TOCItem.ID?
    let bookmarks: [Annotation]
    let highlights: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (EpubTocEntry) -> Void
    let onSelectAnnotation: (Annotation) -> Void
    let onDeleteAnnotation: (Annotation) -> Void

    @State private var showTOC = false
    @State private var tab = NavigatorTab.toc

    var body: some View {
        Button("目录", systemImage: "list.bullet") {
            showTOC.toggle()
        }
        .help("目录")
        .popover(isPresented: $showTOC, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                Picker("面板", selection: $tab) {
                    ForEach(NavigatorTab.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)

                Divider()

                Group {
                    switch tab {
                    case .toc:
                        TOCList(items: toc, current: current) { entry in
                            showTOC = false
                            onSelect(entry)
                        }
                    case .bookmarks:
                        annotationList(.bookmark, bookmarks)
                    case .highlights:
                        annotationList(.highlight, highlights)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 300, height: 460)
        }
    }

    private func annotationList(_ kind: Annotation.Kind, _ annotations: [Annotation]) -> some View {
        AnnotationList(kind: kind, annotations: annotations, progress: progress) { annotation in
            showTOC = false
            onSelectAnnotation(annotation)
        } onDelete: { annotation in
            onDeleteAnnotation(annotation)
        }
    }
}
