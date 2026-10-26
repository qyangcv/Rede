import SwiftUI

enum BookGrid {
    static func layout(width: CGFloat, cardWidth: CGFloat,
                       minSpacing: CGFloat) -> (columns: [GridItem], spacing: CGFloat) {
        let n = max(1, Int((width - minSpacing) / (cardWidth + minSpacing)))
        let spacing = (width - CGFloat(n) * cardWidth) / CGFloat(n + 1)
        let column = GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top)
        return (columns: Array(repeating: column, count: n), spacing: spacing)
    }
}
