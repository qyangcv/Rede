import SwiftUI

struct PreferencesPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section("阅读窗口") {
                Picker("打开新书时", selection: $settings.readerWindowMode) {
                    ForEach(ReaderWindowMode.allCases) { Text($0.name).tag($0) }
                }
                Picker("标题", selection: $settings.readerTitle) {
                    ForEach(ReaderTitle.allCases) { Text($0.name).tag($0) }
                }
                Toggle("启动时恢复上次未关闭的书籍", isOn: $settings.restoreReaderWindows)
                Toggle("在进度条上显示书签", isOn: $settings.showProgressBarBookmarks)
            }
        }
        .formStyle(.grouped)
    }
}
