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
                // 没有背景后图标本身太小，补足 44pt 点击区域
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        // 默认是强调色，和工具栏的图标颜色保持一致
        .foregroundStyle(.primary)
    }
}
