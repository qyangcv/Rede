import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    FontsPane().navigationTitle("字体")
                } label: {
                    Label("字体", systemImage: "f.cursive")
                }
                NavigationLink {
                    SyncPane().navigationTitle("同步")
                } label: {
                    Label("同步", systemImage: "icloud")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
