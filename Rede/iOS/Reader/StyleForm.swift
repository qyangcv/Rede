import SwiftUI

// iOS 的样式面板：用 Form 排列原生控件，样式交给系统按行适配
struct StyleForm: View {
    @Binding var style: ReaderStyle
    @Binding var appearance: Appearance
    @Binding var transition: PageTransition

    var body: some View {
        Form {
            Section {
                LabeledContent("字号") {
                    HStack {
                        Text("\(style.fontScale)%").monospacedDigit()
                        Stepper("字号", value: $style.fontScale, in: ReaderStyle.fontScaleRange,
                                step: ReaderStyle.fontScaleStep)
                            .labelsHidden()
                    }
                }

                Picker("字体", selection: $style.font) {
                    FontOptions()
                }

                if let weight = style.fontWeight, style.font.weights.count > 1 {
                    LabeledContent("粗细") {
                        FontWeightSlider(weights: style.font.weights,
                                         weight: Binding(get: { weight }, set: { style.fontWeight = $0 }))
                    }
                }
            }

            Section {
                LabeledContent("行距") {
                    SpacingPicker(title: "行距", selection: $style.lineSpacing)
                }
                LabeledContent("段距") {
                    SpacingPicker(title: "段距", selection: $style.paraSpacing)
                }
            }

            Section {
                Picker("外观", selection: $appearance) {
                    AppearanceOptions()
                }
                LabeledContent("颜色") {
                    ColorSwatches(selection: $style.background)
                }
                LabeledContent("背景") {
                    PatternSwatches(selection: $style.pattern, background: style.background)
                }
            }

            // 平台只实现了一种翻页方式时不显示
            if PageTransition.allCases.count > 1 {
                Section {
                    LabeledContent("翻页") {
                        TransitionPicker(selection: $transition)
                    }
                }
            }

            Section {
                Button("恢复默认") {
                    style = .default
                }
                .disabled(style == .default)
            }
        }
    }
}
