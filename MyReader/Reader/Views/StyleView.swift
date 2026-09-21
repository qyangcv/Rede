// Reader Style View

import SwiftUI

struct StyleButton: View {
    @Binding var style: ReaderStyle
    var onDismiss: () -> Void = {}

    @State private var isPresented = false

    var body: some View {
        Button("外观", systemImage: "textformat") {
            isPresented.toggle()
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
                    FontSizeStepper(size: $style.fontSize)
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
                    label("背景")
                    HStack(spacing: 6) {
                        ForEach(BackgroundColor.allCases) { item in
                            BackgroundSwatch(background: item,
                                             isSelected: item == style.background) {
                                style.background = item
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

private struct FontSizeStepper: View {
    @Binding var size: Int

    private let range = ReaderStyle.fontSizeRange

    var body: some View {
        HStack(spacing: 9) {
            Button("减小字号", systemImage: "textformat.size.smaller") {
                size = max(size - 1, range.lowerBound)
            }
            .disabled(size <= range.lowerBound)

            Text("\(size)")
                .monospacedDigit()
                .frame(minWidth: 0)

            Button("增大字号", systemImage: "textformat.size.larger") {
                size = min(size + 1, range.upperBound)
            }
            .disabled(size >= range.upperBound)
        }
        .labelStyle(.iconOnly)
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

#Preview("stylePanel") {
    @Previewable @State var style = ReaderStyle.default
    StylePanel(style: $style)
}
