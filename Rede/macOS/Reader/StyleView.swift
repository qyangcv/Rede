import SwiftUI

struct StylePanel: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var pageLayout: ReaderPageLayout
    @Binding var pageMargin: Int

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
                        field("边距") {
                            MarginControl(
                                value: $pageMargin,
                                range: Settings.readerPageMarginRange,
                                defaultValue: Settings.defaultReaderPageMargin
                            )
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

private struct MarginControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let defaultValue: Int

    @State private var dragOrigin: Int?
    @State private var hoveringMinus = false
    @State private var hoveringPlus = false

    private let pointsPerStep: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", label: "减小边距",
                       enabled: value > range.lowerBound, hovering: $hoveringMinus) {
                value = max(value - 1, range.lowerBound)
            }

            Divider()
                .frame(height: 12)

            Text("\(value)%")
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { gesture in
                            let origin = dragOrigin ?? value
                            if dragOrigin == nil { dragOrigin = origin }
                            let delta = Int((gesture.translation.width / pointsPerStep).rounded())
                            value = min(max(origin + delta, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in
                            dragOrigin = nil
                        }
                )
                .onTapGesture(count: 2) {
                    value = defaultValue
                }
                .help("左右拖动调节，双击恢复默认")

            Divider()
                .frame(height: 12)

            stepButton(systemImage: "plus", label: "增大边距",
                       enabled: value < range.upperBound, hovering: $hoveringPlus) {
                value = min(value + 1, range.upperBound)
            }
        }
        .frame(width: 148, height: 24)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("边距")
        .accessibilityValue("\(value)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemImage: String, label: LocalizedStringKey,
                            enabled: Bool, hovering: Binding<Bool>,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 32, height: 24)
                .background(enabled && hovering.wrappedValue ? Color.primary.opacity(0.08) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .onHover { hovering.wrappedValue = $0 }
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
    @Previewable @State var pageMargin = Settings.defaultReaderPageMargin
    StylePanel(style: $style, appearance: $appearance, pageLayout: $pageLayout, pageMargin: $pageMargin)
        .frame(width: 300, height: 500)
}
