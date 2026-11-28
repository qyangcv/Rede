import SwiftUI

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
            Text("字重")
        } tick: { SliderTick($0) }
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

struct HighlightColorDots: View {
    let selection: HighlightColor?
    var size: CGFloat = 14
    var spacing: CGFloat = 8
    let onSelect: (HighlightColor) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(HighlightColor.allCases) { color in
                let selected = color == selection
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: size * 0.52, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct HighlightColorFilterBar: View {
    @Binding var selection: HighlightColor?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                selection = nil
            } label: {
                Text("全部")
                    .font(.caption.weight(selection == nil ? .semibold : .regular))
                    .foregroundStyle(selection == nil ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selection == nil ? Color.primary.opacity(0.1) : .clear, in: Capsule())
            }
            .buttonStyle(.plain)

            HighlightColorDots(selection: selection, size: 13, spacing: 6) { color in
                selection = selection == color ? nil : color
            }
        }
    }
}
