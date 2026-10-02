import SwiftUI

struct TOCItem: Identifiable {
    let entry: EpubTocEntry
    let path: [EpubTocEntry]
    var depth: Int { path.count - 1 }
    var id: String { entry.id }

    static func flatten(_ entries: [EpubTocEntry], ancestors: [EpubTocEntry] = []) -> [TOCItem] {
        entries.flatMap { entry in
            let path = ancestors + [entry]
            return [TOCItem(entry: entry, path: path)] + flatten(entry.children, ancestors: path)
        }
    }
}

struct TOCButton: View {
    let toc: [TOCItem]
    let current: TOCItem.ID?
    let onSelect: (EpubTocEntry) -> Void

    @State private var showTOC = false

    var body: some View {
        Button("目录", systemImage: "list.bullet") {
            showTOC.toggle()
        }
        .help("目录")
        .popover(isPresented: $showTOC, arrowEdge: .bottom) {
            TOCList(items: toc, current: current) { entry in
                showTOC = false
                onSelect(entry)
            }
            .frame(width: 300, height: 460)
        }
    }
}

struct TOCList: View {
    let items: [TOCItem]
    let current: TOCItem.ID?
    let onSelect: (EpubTocEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                ContentUnavailableView("没有目录", systemImage: "list.bullet")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                TOCRow(title: item.entry.title, depth: item.depth,
                                       isCurrent: item.id == current) {
                                    onSelect(item.entry)
                                }
                                .id(item.id)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onAppear {
                        if let current { proxy.scrollTo(current, anchor: .center) }
                    }
                }
            }
        }
    }
}

private struct TOCRow: View {
    let title: String
    let depth: Int
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title.isEmpty ? "未命名章节" : title)
                .font(depth == 0 ? .body : .callout)
                .foregroundStyle(depth == 0 ? HierarchicalShapeStyle.primary : .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10 + CGFloat(depth) * 16)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .fontWeight(isCurrent ? .semibold : nil)
                .background(isCurrent ? Color.accentColor.opacity(0.15)
                            : isHovering ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}

#Preview("TOCList") {
    TOCList(items: TOCItem.flatten([
        EpubTocEntry(id: "0", title: "第一部 面壁者", path: "a.xhtml", fragment: nil, children: [
            EpubTocEntry(id: "0.0", title: "序章", path: "a.xhtml", fragment: "p1", children: []),
            EpubTocEntry(id: "0.1", title: "上篇", path: "b.xhtml", fragment: nil, children: []),
        ]),
        EpubTocEntry(id: "1", title: "第二部 咒语", path: "c.xhtml", fragment: nil, children: []),
    ]), current: "0.1", onSelect: { print($0.title) })
}
