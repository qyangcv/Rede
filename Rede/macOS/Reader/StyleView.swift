import SwiftUI

struct StylePanel: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var pageLayout: ReaderPageLayout

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("文字") {
                        HStack(spacing: 0) {
                            field("字体") {
                                Menu {
                                    Picker("字体", selection: $style.font) { FontOptions() }
                                        .pickerStyle(.inline)
                                        .labelsHidden()
                                } label: {
                                    Text(style.font.name)
                                }
                                .menuStyle(.button)
                                .fixedSize()
                            }
                            Spacer(minLength: 12)
                            stepperField("字号", display: "\(style.fontScale)%", value: $style.fontScale,
                                         range: ReaderStyle.fontScaleRange, step: ReaderStyle.fontScaleStep,
                                         widthSample: "\(ReaderStyle.fontScaleRange.upperBound)%")
                                .fixedSize()
                        }
                        if let weight = style.fontWeight, style.font.weights.count > 1 {
                            field("字重") {
                                FontWeightSlider(weights: style.font.weights,
                                                 weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                                Text("\(weight)").monospacedDigit()
                            }
                        }
                    }

                    Divider()

                    section("排版") {
                        HStack(spacing: 16) {
                            spacingControl("行距", selection: $style.lineSpacing)
                            spacingControl("段距", selection: $style.paraSpacing)
                        }
                        field("布局") {
                            Picker("布局", selection: $pageLayout) {
                                ForEach(ReaderPageLayout.allCases) { item in
                                    Text(item.name).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    section("外观") {
                        field("模式") {
                            Picker("外观模式", selection: $appearance) {
                                ForEach(Appearance.allCases) { item in
                                    Label(item.name, systemImage: item.icon).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        field("背景") {
                            ColorSwatches(selection: $style.background)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            Button("重置") { style = .default }
                .disabled(style == .default)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private func field(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        LabeledContent(content: content) {
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func stepperField(_ title: LocalizedStringKey, display: String, value: Binding<Int>,
                              range: ClosedRange<Int>, step: Int = 1, widthSample: String,
                              alignment: Alignment = .trailing) -> some View {
        field(title) {
            HStack(spacing: 8) {
                ZStack(alignment: alignment) {
                    Text(widthSample).hidden()
                    Text(display)
                }
                .monospacedDigit()
                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .opacity(contrast == .increased ? 1 : 0.7)
                    .accessibilityValue(Text(display))
            }
        }
    }

    private func spacingControl(_ title: LocalizedStringKey, selection: Binding<Spacing>) -> some View {
        let levels = Spacing.allCases
        let index = Binding(get: { levels.firstIndex(of: selection.wrappedValue)! },
                            set: { selection.wrappedValue = levels[$0] })
        return stepperField(title, display: selection.wrappedValue.name, value: index,
                            range: 0...(levels.count - 1), widthSample: Spacing.relaxed.name, alignment: .center)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("stylePanel") {
    @Previewable @State var style = ReaderStyle.default
    @Previewable @State var appearance = Appearance.system
    @Previewable @State var pageLayout = ReaderPageLayout.auto
    StylePanel(style: $style, appearance: $appearance, pageLayout: $pageLayout)
        .frame(width: 300, height: 500)
}
