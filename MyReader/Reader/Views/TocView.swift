import SwiftUI

struct TOCButton: View {
    let toc: [EpubTocEntry]
    let onSelect: (EpubTocEntry) -> Void

    @State private var showTOC = false

    var body: some View {
        Button("目录", systemImage: "list.bullet") {
            showTOC.toggle()
        }
        .help("目录")
        .popover(isPresented: $showTOC, arrowEdge: .bottom) {
            TOCList(toc: toc) { entry in
                showTOC = false
                onSelect(entry)
            }
        }
    }
}

struct TOCList: View {
    let onSelect: (EpubTocEntry) -> Void
    private let rows: [Row]

    init(toc: [EpubTocEntry], onSelect: @escaping (EpubTocEntry) -> Void) {
        self.onSelect = onSelect
        self.rows = Self.flatten(toc)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("目录")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if rows.isEmpty {
                ContentUnavailableView("没有目录", systemImage: "list.bullet")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            TOCRow(title: row.entry.title, depth: row.depth) {
                                onSelect(row.entry)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 300, height: 460)
    }

    struct Row: Identifiable {
        let entry: EpubTocEntry
        let depth: Int
        var id: String { entry.id }
    }

    private static func flatten(_ entries: [EpubTocEntry], depth: Int = 0) -> [Row] {
        entries.flatMap { entry in
            [Row(entry: entry, depth: depth)] + flatten(entry.children, depth: depth + 1)
        }
    }
}

private struct TOCRow: View {
    let title: String
    let depth: Int
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
                .background(isHovering ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}


#Preview("TOCList") {
    TOCList(toc: [
        EpubTocEntry(id: "0", title: "第一部 面壁者", path: "a.xhtml", fragment: nil, children: [
            EpubTocEntry(id: "0.0", title: "序章", path: "a.xhtml", fragment: "p1", children: []),
            EpubTocEntry(id: "0.1", title: "上篇", path: "b.xhtml", fragment: nil, children: []),
        ]),
        EpubTocEntry(id: "1", title: "第二部 咒语", path: "c.xhtml", fragment: nil, children: []),
    ], onSelect: { print($0.title) })
}
