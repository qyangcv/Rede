import SwiftUI

struct StylePanel: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("文字") {
                        LabeledContent("字体") {
                            Picker("字体", selection: $style.font) { FontOptions() }
                                .pickerStyle(.menu)
                                .labelsHidden()
                        }
                        LabeledContent("字号") {
                            HStack(spacing: 10) {
                                FontScaleButtons(scale: $style.fontScale, showsScale: true)
                            }
                            .labelStyle(.iconOnly)
                        }
                        if let weight = style.fontWeight, style.font.weights.count > 1 {
                            LabeledContent("字重") {
                                FontWeightSlider(weights: style.font.weights,
                                                 weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                                Text("\(weight)").monospacedDigit()
                            }
                        }
                    }

                    Divider()

                    section("间距") {
                        spacingControl("行距", selection: $style.lineSpacing)
                        spacingControl("段距", selection: $style.paraSpacing)
                    }

                    Divider()

                    section("外观") {
                        LabeledContent("模式") {
                            Picker("外观模式", selection: $appearance) { AppearanceOptions() }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        LabeledContent("背景") {
                            ColorSwatches(selection: $style.background)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            Button("恢复默认") { style = .default }
                .disabled(style == .default)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private func spacingControl(_ title: String, selection: Binding<Spacing>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            SpacingPicker(title: title, selection: selection)
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

struct FontScaleButtons: View {
    @Binding var scale: Int
    var showsScale = false
    var assignsKeyboardShortcuts = false

    private let range = ReaderStyle.fontScaleRange
    private let step = ReaderStyle.fontScaleStep

    var body: some View {
        if showsScale {
            decrease
            Text("\(scale)%").monospacedDigit()
            increase
        } else {
            increase
            decrease
        }
    }

    private var increase: some View {
        Button("放大字体", systemImage: "textformat.size.larger") {
            scale = min(scale + step, range.upperBound)
        }
        .keyboardShortcut(assignsKeyboardShortcuts ? KeyboardShortcut("+") : nil)
        .disabled(scale >= range.upperBound)
    }

    private var decrease: some View {
        Button("缩小字体", systemImage: "textformat.size.smaller") {
            scale = max(scale - step, range.lowerBound)
        }
        .keyboardShortcut(assignsKeyboardShortcuts ? KeyboardShortcut("-") : nil)
        .disabled(scale <= range.lowerBound)
    }
}

struct FontOptions: View {
    var body: some View {
        let fonts = ReaderFont.allCases.filter(\.isAvailable)
        Section("内置字体") {
            ForEach(fonts.filter(\.isBuiltin)) { Text($0.name).tag($0) }
        }
        let thirdParty = fonts.filter { !$0.isBuiltin }
        if !thirdParty.isEmpty {
            Section("三方字体") {
                ForEach(thirdParty) { Text($0.name).tag($0) }
            }
        }
    }
}

struct AppearanceOptions: View {
    var body: some View {
        ForEach(Appearance.allCases) { item in
            Label(item.name, systemImage: item.icon)
                .tag(item)
        }
    }
}

#Preview("stylePanel") {
    @Previewable @State var style = ReaderStyle.default
    @Previewable @State var appearance = Appearance.system
    StylePanel(style: $style, appearance: $appearance)
        .frame(width: 300, height: 500)
}
