import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // 版本号取自 Info.plist，由 MARKETING_VERSION / CURRENT_PROJECT_VERSION 生成
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } footer: {
                    Text("版本 \(Self.version)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
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
