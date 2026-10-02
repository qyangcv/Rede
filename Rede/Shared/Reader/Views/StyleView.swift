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
                .frame(width: 290)
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
                            SliderAccessory { Text("\(weight)").monospacedDigit() }
                        }
                    }
                }

                Divider()

                GridRow {
                    label("行距")
                    SpacingPicker(title: "行距", selection: $style.lineSpacing)
                }

                GridRow {
                    label("段距")
                    SpacingPicker(title: "段距", selection: $style.paraSpacing)
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

            Text("\(range.upperBound)%")
                .monospacedDigit()
                .hidden()
                .overlay {
                    Text("\(scale)%").monospacedDigit()
                }

            Button("增大字号", systemImage: "textformat.size.larger") {
                scale = min(scale + step, range.upperBound)
            }
            .disabled(scale >= range.upperBound)
        }
        .labelStyle(.iconOnly)
    }
}

struct FontWeightSlider: View {
    let weights: [Int]
    @Binding var weight: Int

    private var index: Binding<Double> {
        Binding(
            get: { Double(weights.firstIndex(of: weight) ?? 0) },
            set: { weight = weights[Int($0.rounded())] }
        )
    }

    var body: some View {
        Slider(value: index, in: 0...Double(weights.count - 1), step: 1) {
            Text("粗细")
        } tick: { SliderTick($0) }
        .labelsHidden()
    }
}

/// 滑块尾部附件：按最宽的取值占位，取值变化时宽度不变，多条滑块的轨道也能首尾对齐
struct SliderAccessory<Content: View>: View {
    var placeholder = "900"
    var alignment: Alignment = .trailing
    @ViewBuilder var content: Content

    var body: some View {
        Text(placeholder)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: alignment) { content }
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

struct SpacingPicker: View {
    let title: String
    @Binding var selection: Spacing

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Spacing.allCases) { level in
                Text(level.name).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct TransitionPicker: View {
    @Binding var selection: PageTransition

    var body: some View {
        Picker("翻页", selection: $selection) {
            ForEach(PageTransition.allCases) { item in
                Text(item.name).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct ColorSwatches: View {
    @Binding var selection: BackgroundColor

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BackgroundColor.allCases) { item in
                BackgroundSwatch(color: item.swatch(for: colorScheme), name: item.name,
                                 isSelected: item == selection) {
                    selection = item
                }
            }
        }
    }
}

struct PatternSwatches: View {
    @Binding var selection: BackgroundPattern
    let background: BackgroundColor

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BackgroundPattern.allCases) { item in
                PatternSwatch(pattern: item, color: background.swatch(for: colorScheme),
                              isSelected: item == selection) {
                    selection = item
                }
            }
        }
    }
}

private struct BackgroundSwatch: View {
    let color: Color
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

private struct PatternSwatch: View {
    let pattern: BackgroundPattern
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    private var image: Image? {
        pattern.file
            .flatMap { Bundle.main.url(forResource: $0, withExtension: nil) }
            .flatMap(Image.init(fileURL:))
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 36, height: 20)
                .overlay(alignment: .topTrailing) {
                    if let image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(pattern.name)
    }
}

#Preview("stylePanel") {
    @Previewable @State var style = ReaderStyle.default
    @Previewable @State var appearance = Appearance.system
    @Previewable @State var transition = PageTransition.default
    StylePanel(style: $style, appearance: $appearance, transition: $transition)
}
