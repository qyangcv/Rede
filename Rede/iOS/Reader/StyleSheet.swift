import SwiftUI

// iOS 的样式面板：要对照正文调整，所以尽量矮。每项占一行，不分组
struct StyleSheet: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var transition: PageTransition
    @Binding var brightness: Double
    @State private var choosingFont = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                label("亮度")
                Slider(value: $brightness, in: 0.3...1) {
                    Text("亮度")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
            }

            GridRow {
                label("字体")
                // 字体菜单与下方控件左对齐，有底色的 Stepper 与下方分段控件右对齐
                HStack {
                    Button { choosingFont = true } label: {
                        HStack(spacing: 4) {
                            Text(style.font.name)
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
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
                    label("粗细")
                    FontWeightSlider(weights: style.font.weights,
                                     weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                }
            }

            GridRow {
                label("行距")
                SpacingPicker(title: "行距", selection: $style.lineSpacing)
            }

            GridRow {
                label("段距")
                SpacingPicker(title: "段距", selection: $style.paraSpacing)
            }

            GridRow {
                label("外观")
                Picker("外观", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // 颜色和背景各占半行，背景从中线开始
            GridRow {
                label("颜色")
                HStack(spacing: 16) {
                    ColorSwatches(selection: $style.background)
                        .frame(maxWidth: .infinity, alignment: .leading)
//                    HStack(spacing: 16) {
//                        label("背景")
//                        PatternSwatches(selection: $style.pattern, background: style.background)
//                    }
//                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 平台只实现了一种翻页方式时不显示
            if PageTransition.allCases.count > 1 {
                GridRow {
                    label("翻页")
                    TransitionPicker(selection: $transition)
                }
            }
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 8)
        .fontDropdown(isPresented: $choosingFont, selection: $style.font)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
