import SwiftUI

struct AppearanceButton: View {
    @Binding var appearance: Appearance

    var body: some View {
        Menu {
            Picker("外观", selection: $appearance) {
                ForEach(Appearance.allCases) { item in
                    Label(item.name, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("外观", systemImage: appearance.icon)
        }
        .menuIndicator(.hidden)
        .help("外观")
    }
}
