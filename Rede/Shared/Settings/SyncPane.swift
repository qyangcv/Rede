import SwiftUI

struct SyncPane: View {
    @Bindable private var settings = Settings.shared

    private var monitor: SyncMonitor { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("开启 iCloud 同步", isOn: $settings.iCloudSync)
                if CloudSync.isActive {
                    LabeledContent("状态", value: monitor.summary)
                    if let date = monitor.lastSynced {
                        LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .standard))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在登录同一 Apple ID 的设备之间同步书籍、书籍信息和阅读进度，阅读设置不同步。")
                    if settings.iCloudSync != CloudSync.isActive {
                        Text("重新启动 App 后生效").foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
