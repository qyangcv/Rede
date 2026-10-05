import SwiftUI

struct LibraryMenu: View {
    @Binding var sort: LibrarySort
    @Binding var layout: LibraryLayout
    @Binding var appearance: Appearance
    let onSelect: () -> Void
    let onSettings: () -> Void

    var body: some View {
        Menu {
            Button("批量管理", systemImage: "checkmark.circle", action: onSelect)

            Picker("陈列方式", selection: $layout) {
                ForEach(LibraryLayout.allCases) { item in
                    Label(item.name, systemImage: item.icon).tag(item)
                }
            }
            .labelsVisibility(.visible)

            Picker("外观", selection: $appearance) {
                ForEach(Appearance.allCases) { item in
                    Label(item.name, systemImage: item.icon).tag(item)
                }
            }
            .labelsVisibility(.visible)

            Picker("排序方式", selection: $sort) {
                ForEach(LibrarySort.allCases) { item in
                    Text(item.name).tag(item)
                }
            }
            .labelsVisibility(.visible)

            Button("设置", systemImage: "gearshape", action: onSettings)
        } label: {
            Label("更多", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
    }
}
