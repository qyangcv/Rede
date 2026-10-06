import SwiftUI

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
