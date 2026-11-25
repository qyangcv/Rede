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
            }
        }
        .formStyle(.grouped)
    }
}
