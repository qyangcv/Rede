import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
        turn(swipe.direction == .left ? .next : .prev)
    }
    #endif
}

#if os(iOS)
extension InstantTurner: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !reader.selecting
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
