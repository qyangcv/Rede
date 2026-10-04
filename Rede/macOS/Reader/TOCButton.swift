import SwiftUI

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
