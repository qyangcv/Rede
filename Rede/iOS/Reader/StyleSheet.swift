import SwiftUI

struct StyleSheet: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var transition: PageTransition
    @Binding var brightness: Double
    @Binding var showsStatus: Bool
    @State private var choosingFont = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                label("亮度")
                HStack(spacing: 9) {
                    Slider(value: $brightness, in: 0.3...1) {
                        Text("亮度")
                    }
                    .labelsHidden()
                    sliderAccessory { Image(systemName: "sun.max") }
                }
            }

            GridRow {
                label("字体")
                HStack {
                    Button { choosingFont = true } label: {
                        HStack(spacing: 4) {
                            Text(style.font.name)
                            Image(systemName: "chevron.down")
                                .imageScale(.small)
                                .rotationEffect(.degrees(choosingFont ? 180 : 0))
                        }
                    }
                    .tint(.primary)
                    .fixedSize()
                    .anchorPreference(key: FontButtonAnchor.self, value: .bounds) { $0 }
                    Spacer()
                    Text("\(style.fontScale)%").monospacedDigit()
                    Stepper("字号", value: $style.fontScale, in: ReaderStyle.fontScaleRange,
                            step: ReaderStyle.fontScaleStep)
                        .labelsHidden()
                }
                .font(.footnote)
            }

            if let weight = style.fontWeight, style.font.weights.count > 1 {
                GridRow {
                    label("字重")
                    HStack(spacing: 9) {
                        FontWeightSlider(weights: style.font.weights,
                                         weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                        sliderAccessory { Text(weightName(weight)).font(.footnote) }
                    }
                }
            }

            GridRow {
                label("行距")
                spacingPicker("行距", selection: $style.lineSpacing)
            }

            GridRow {
                label("段距")
                spacingPicker("段距", selection: $style.paraSpacing)
            }

            GridRow {
                label("外观")
                Picker("外观", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            GridRow {
                label("颜色")
                ColorSwatches(selection: $style.background)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GridRow {
                label("翻页")
                Picker("翻页", selection: $transition) {
                    ForEach(PageTransition.allCases) { item in
                        Text(item.name).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            GridRow {
                HStack(spacing: 16) {
                    label("时间和电量")
                    Picker("时间和电量", selection: $showsStatus) {
                        Text("显示").tag(true)
                        Text("隐藏").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .gridCellColumns(2)
            }
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 8)
        .fontDropdown(isPresented: $choosingFont, selection: $style.font, background: style.background)
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

    private func sliderAccessory(@ViewBuilder content: () -> some View) -> some View {
        Text("较细")
            .hidden()
            .overlay { content() }
    }

    private func weightName(_ weight: Int) -> String {
        let weights = style.font.weights
        let names = weights.count == 5 ? ["细", "较细", "适中", "较粗", "粗"] : ["细", "适中", "粗"]
        return weights.firstIndex(of: weight).map { names[$0] } ?? ""
    }
}
