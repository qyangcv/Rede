import SwiftUI

struct StyleButton: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var transition: PageTransition
    var onDismiss: () -> Void = {}

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("样式", systemImage: "textformat")
                .environment(\.locale, Locale(identifier: "en"))
        }
        .help("样式")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StylePanel(style: $style, appearance: $appearance, transition: $transition)
                .frame(minWidth: 210)
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { onDismiss() }
        }
    }
}

struct StylePanel: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var transition: PageTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    label("字号")
                    FontScaleStepper(scale: $style.fontScale)
                }

                GridRow {
                    label("字体")
                    Menu(style.font.name) {
                        Picker("字体", selection: $style.font) {
                            FontOptions()
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let weight = style.fontWeight, style.font.weights.count > 1 {
                    GridRow {
                        label("粗细")
                        HStack(spacing: 9) {
                            FontWeightSlider(weights: style.font.weights,
                                             weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                            Text("\(weight)").monospacedDigit()
                        }
                    }
                }

                Divider()

                GridRow {
                    label("行距")
                    SpacingPicker(title: "行距", style: .menu, selection: $style.lineSpacing)
                }

                GridRow {
                    label("段距")
                    SpacingPicker(title: "段距", style: .menu, selection: $style.paraSpacing)
                }

                Divider()

                GridRow {
                    label("外观")
                    Picker("外观", selection: $appearance) {
                        AppearanceOptions()
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .labelsHidden()
                }

                GridRow {
                    label("颜色")
                    ColorSwatches(selection: $style.background)
                }

                if PageTransition.allCases.count > 1 {
                    Divider()

                    GridRow {
                        label("翻页")
                        TransitionPicker(selection: $transition)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("恢复默认") {
                    style = .default
                }
                .disabled(style == .default)
            }
        }
        .padding(16)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}

private struct FontScaleStepper: View {
    @Binding var scale: Int

    private let range = ReaderStyle.fontScaleRange
    private let step = ReaderStyle.fontScaleStep

    var body: some View {
        HStack(spacing: 9) {
            Button("减小字号", systemImage: "textformat.size.smaller") {
                scale = max(scale - step, range.lowerBound)
            }
            .disabled(scale <= range.lowerBound)

            Text("\(scale)%").monospacedDigit()

            Button("增大字号", systemImage: "textformat.size.larger") {
                scale = min(scale + step, range.upperBound)
            }
            .disabled(scale >= range.upperBound)
        }
        .labelStyle(.iconOnly)
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
    @Previewable @State var transition = PageTransition.default
    StylePanel(style: $style, appearance: $appearance, transition: $transition)
}
