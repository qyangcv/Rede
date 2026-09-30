import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("字体", systemImage: "f.cursive") {
                FontsPane()
                    .frame(width: 480, height: 300)
            }
            Tab("同步", systemImage: "icloud") {
                SyncPane()
                    .frame(width: 480, height: 300)
            }
        }
    }
}

#Preview {
    SettingsView()
}
