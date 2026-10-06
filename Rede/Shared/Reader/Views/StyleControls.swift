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
            Text("粗细")
        } tick: { SliderTick($0) }
        .labelsHidden()
    }
}

struct SpacingPicker: View {
    enum Style {
        case segmented, menu
    }

    let title: String
    var style: Style = .segmented
    @Binding var selection: Spacing

    var body: some View {
        switch style {
        case .segmented:
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
        case .menu:
            picker
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(Spacing.allCases) { level in
                Text(level.name).tag(level)
            }
        }
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
