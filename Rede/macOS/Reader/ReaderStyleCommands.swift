import SwiftUI

struct ReaderStyleCommands: View {
    @FocusedValue(\.readerMenuContext) private var context
    @Bindable private var settings = Settings.shared

    var body: some View {
        Button("打开样式面板") { context?.showStyle() }
            .disabled(context == nil)

        Divider()

        Menu("外观") {
            Picker("外观", selection: $settings.appearance) {
                Text("跟随系统").tag(Appearance.system)
                ForEach(Appearance.allCases.filter { $0 != .system }) { appearance in
                    Text(appearance.name).tag(appearance)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Menu("背景色") {
            Picker("背景色", selection: $settings.readerStyle.background) {
                ForEach(BackgroundColor.allCases) { color in
                    Text(color.name).tag(color)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)

        Divider()

        Menu("窗口标题") {
            Picker("窗口标题", selection: $settings.readerTitle) {
                ForEach(ReaderTitle.allCases) { title in
                    Text(title.name).tag(title)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)

        Menu("布局") {
            Picker("布局", selection: $settings.readerPageLayout) {
                ForEach(ReaderPageLayout.allCases) { layout in
                    Text(layout.name).tag(layout)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)

        Divider()

        Menu("字体") {
            Picker("字体", selection: $settings.readerStyle.font) {
                FontOptions()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)

        let weights = settings.readerStyle.font.weights
        Menu("字重") {
            Picker("字重", selection: $settings.readerStyle.fontWeight) {
                ForEach(weights, id: \.self) { value in
                    Text(value.formatted()).tag(Optional(value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil || weights.count < 2)

        Button("放大字体", systemImage: "textformat.size.larger") {
            settings.readerStyle.fontScale = min(settings.readerStyle.fontScale + ReaderStyle.fontScaleStep,
                                                 ReaderStyle.fontScaleRange.upperBound)
        }
        .keyboardShortcut("+")
        .disabled(context == nil || settings.readerStyle.fontScale >= ReaderStyle.fontScaleRange.upperBound)
        Button("缩小字体", systemImage: "textformat.size.smaller") {
            settings.readerStyle.fontScale = max(settings.readerStyle.fontScale - ReaderStyle.fontScaleStep,
                                                 ReaderStyle.fontScaleRange.lowerBound)
        }
        .keyboardShortcut("-")
        .disabled(context == nil || settings.readerStyle.fontScale <= ReaderStyle.fontScaleRange.lowerBound)
        Button("默认大小") { settings.readerStyle.fontScale = ReaderStyle.default.fontScale }
            .disabled(context == nil || settings.readerStyle.fontScale == ReaderStyle.default.fontScale)

        Divider()

        spacingMenu("行距", selection: $settings.readerStyle.lineSpacing)
        spacingMenu("段距", selection: $settings.readerStyle.paraSpacing)

        Divider()

        Button("重置样式") { settings.readerStyle = .default }
            .disabled(context == nil || settings.readerStyle == .default)
    }

    private func spacingMenu(_ title: LocalizedStringKey, selection: Binding<Spacing>) -> some View {
        Menu(title) {
            Picker(title, selection: selection) {
                ForEach(Spacing.allCases) { spacing in
                    Text(spacing.name).tag(spacing)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)
    }
}
