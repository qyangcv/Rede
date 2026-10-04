import SwiftUI

enum NavigatorTab: CaseIterable, Identifiable {
    case toc, bookmarks

    var id: Self { self }

    var name: String {
        switch self {
        case .toc: "目录"
        case .bookmarks: "书签"
        }
    }
}

struct TOCButton: View {
    let toc: [TOCItem]
    let current: TOCItem.ID?
    let bookmarks: [Annotation]
    let progress: (Annotation) -> Double?
    let onSelect: (EpubTocEntry) -> Void
    let onSelectBookmark: (Annotation) -> Void
    let onDeleteBookmark: (Annotation) -> Void

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

                switch tab {
                case .toc:
                    TOCList(items: toc, current: current) { entry in
                        showTOC = false
                        onSelect(entry)
                    }
                case .bookmarks:
                    BookmarkList(bookmarks: bookmarks, progress: progress) { bookmark in
                        showTOC = false
                        onSelectBookmark(bookmark)
                    } onDelete: { bookmark in
                        onDeleteBookmark(bookmark)
                    }
                }
            }
            .frame(width: 300, height: 460)
        }
    }
}
