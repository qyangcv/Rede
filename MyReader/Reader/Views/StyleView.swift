// Reader Style View

import SwiftUI

struct StyleButton: View {
    @Binding var style: ReaderStyle
    var onDismiss: () -> Void = {}

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("外观", systemImage: "textformat")
                .environment(\.locale, Locale(identifier: "en"))
        }
        .help("外观")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StylePanel(style: $style)
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { onDismiss() }
        }
    }
}

struct StylePanel: View {
    @Binding var style: ReaderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    label("字号")
                    FontScaleStepper(scale: $style.fontScale)
                }

                GridRow {
                    label("字体")
                    Picker("字体", selection: $style.font) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.name).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let weight = style.fontWeight {
                    GridRow {
                        label("粗细")
                        FontWeightSlider(weights: style.font.weights,
                                         weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                    }
                }

                Divider()

                GridRow {
                    label("行距")
                    spacingPicker("行距", selection: $style.lineSpacing)
                }

                GridRow {
                    label("段距")
                    spacingPicker("段距", selection: $style.paraSpacing)
                }

                Divider()

                GridRow {
                    label("颜色")
                    HStack(spacing: 6) {
                        ForEach(BackgroundColor.allCases) { item in
                            BackgroundSwatch(background: item,
                                             isSelected: item == style.background) {
                                style.background = item
                            }
                        }
                    }
                }

                GridRow {
                    label("背景")
                    HStack(spacing: 6) {
                        ForEach(BackgroundPattern.allCases) { item in
                            PatternSwatch(pattern: item, color: style.background.swatch,
                                          isSelected: item == style.pattern) {
                                style.pattern = item
                            }
                        }
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
        .frame(width: 290)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }

    private func spacingPicker(_ title: String, selection: Binding<Spacing>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Spacing.allCases) { level in
                Text(level.name).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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

private struct FontWeightSlider: View {
    let weights: [Int]
    @Binding var weight: Int

    private var index: Binding<Double> {
        Binding(
            get: { Double(weights.firstIndex(of: weight) ?? 0) },
            set: { weight = weights[Int($0.rounded())] }
        )
    }

    var body: some View {
        HStack(spacing: 9) {
            Slider(value: index, in: 0...Double(weights.count - 1), step: 1)
            Text("900")
                .monospacedDigit()
                .hidden()
                .overlay(alignment: .trailing) {
                    Text("\(weight)").monospacedDigit()
                }
        }
    }
}

private struct BackgroundSwatch: View {
    let background: BackgroundColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(background.swatch)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                .frame(width: 24, height: 24)
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(background.name)
    }
}

private struct PatternSwatch: View {
    let pattern: BackgroundPattern
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    private var image: NSImage? {
        pattern.file
            .flatMap { Bundle.main.url(forResource: $0, withExtension: nil) }
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 36, height: 20)
                .overlay(alignment: .topTrailing) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32) // 背景缩略图放大倍数
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
    StylePanel(style: $style)
}
