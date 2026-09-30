import SwiftUI
#if os(iOS)
import UIKit
#endif

// 无动画：直接让主 WebView 翻页
final class InstantTurner: NSObject, PageTurner {
    private let reader: Reader
    #if os(iOS)
    private var swipes: [UISwipeGestureRecognizer] = []
    #endif

    init(reader: Reader) {
        self.reader = reader
        super.init()
        #if os(iOS)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            swipe.direction = direction
            swipe.delegate = self
            reader.webView.addGestureRecognizer(swipe)
            swipes.append(swipe)
        }
        #endif
    }

    var pages: PageRenderer? { nil }
    var layer: AnyView { AnyView(EmptyView()) }

    func turn(_ direction: PageDirection) {
        reader.turn(direction.step)
    }

    func detach() {
        #if os(iOS)
        swipes.forEach { reader.webView.removeGestureRecognizer($0) }
        swipes = []
        #endif
    }

    #if os(iOS)
    // 左滑下一页，右滑上一页
    @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
        turn(swipe.direction == .left ? .next : .prev)
    }
    #endif
}

#if os(iOS)
extension InstantTurner: UIGestureRecognizerDelegate {
    // 与 WebView 自带的手势（选字等）同时识别
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
