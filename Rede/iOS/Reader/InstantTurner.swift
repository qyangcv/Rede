import SwiftUI
import UIKit

final class InstantTurner: NSObject, PageTurner {
    private let reader: Reader
    private var swipes: [UISwipeGestureRecognizer] = []

    init(reader: Reader) {
        self.reader = reader
        super.init()
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            swipe.direction = direction
            swipe.delegate = self
            reader.webView.addGestureRecognizer(swipe)
            swipes.append(swipe)
        }
    }

    var pages: PageRenderer? { nil }
    var layer: AnyView { AnyView(EmptyView()) }

    func turn(_ direction: PageDirection) {
        reader.turn(direction.step)
    }

    func detach() {
        swipes.forEach { reader.webView.removeGestureRecognizer($0) }
        swipes = []
    }

    @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
        turn(swipe.direction == .left ? .next : .prev)
    }
}

extension InstantTurner: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !reader.selecting
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
