import SwiftUI

enum BookGrid {
    // 卡片定宽，按可用宽度决定列数，剩余空间均分给列间距和左右边距
    static func layout(width: CGFloat, cardWidth: CGFloat,
                       minSpacing: CGFloat) -> (columns: [GridItem], spacing: CGFloat) {
        let n = max(1, Int((width - minSpacing) / (cardWidth + minSpacing)))
        let spacing = (width - CGFloat(n) * cardWidth) / CGFloat(n + 1)
        let column = GridItem(.fixed(cardWidth), spacing: spacing, alignment: .top)
        return (columns: Array(repeating: column, count: n), spacing: spacing)
    }
}
