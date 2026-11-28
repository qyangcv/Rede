import SwiftUI

struct PreferencesPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section("书库") {
                Toggle(isOn: $settings.useMetadataTitle) {
                    Text("自动识别书籍元信息中的标题")
                    Text("关闭时，优先使用文件名作为书名；开启时，优先使用书籍元信息中的书名")
                }
            }

            Section("阅读窗口") {
                Picker("打开新书时", selection: $settings.readerWindowMode) {
                    ForEach(ReaderWindowMode.allCases) { Text($0.name).tag($0) }
                }
                Picker("标题", selection: $settings.readerTitle) {
                    ForEach(ReaderTitle.allCases) { Text($0.name).tag($0) }
                }
                Toggle("启动时恢复上次未关闭的书籍", isOn: $settings.restoreReaderWindows)
                Toggle("在进度条上显示书签", isOn: $settings.showProgressBarBookmarks)
                Toggle(isOn: $settings.showMarginNotes) {
                    Text("在页边显示笔记")
                    Text("单栏且空间充足时")
                }
            }
        }
        .formStyle(.grouped)
    }
}
