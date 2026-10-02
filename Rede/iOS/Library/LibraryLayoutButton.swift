import SwiftUI

struct LibraryLayoutButton: View {
    @Binding var layout: LibraryLayout

    var body: some View {
        Menu {
            Picker("陈列方式", selection: $layout) {
                ForEach(LibraryLayout.allCases) { item in
                    Label(item.name, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("陈列方式", systemImage: layout.icon)
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .foregroundStyle(.primary)
    }
}
