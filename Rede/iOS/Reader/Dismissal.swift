import SwiftUI

@MainActor
@Observable
final class Dismissal {
    private static let pullDistance: CGFloat = 120
    private static let pullVelocity: CGFloat = 800
    private var snapshot: PullSnapshot?

    var isActive: Bool { snapshot != nil }

    func gesture(for webView: UIView, shouldBegin: @escaping () -> Bool,
                 onClose: @escaping () -> Void) -> some UIGestureRecognizerRepresentable {
        PullDown(webView: webView, shouldBegin: shouldBegin,
                 onChange: { self.pulling($0, in: webView.window) },
                 onEnd: { self.pulled($0, velocity: $1, in: webView.window, onClose: onClose) })
    }

    private func pulling(_ distance: CGFloat, in window: UIWindow?) {
        if snapshot == nil { snapshot = PullSnapshot(window: window) }
        snapshot?.move(to: max(0, distance))
    }

    private func pulled(_ distance: CGFloat, velocity: CGFloat, in window: UIWindow?, onClose: @escaping () -> Void) {
        if distance > Self.pullDistance || velocity > Self.pullVelocity {
            close(in: window, onClose: onClose)
        } else if let snapshot {
            snapshot.move(to: 0, animation: .spring) {
                guard snapshot.offset == 0 else { return }
                snapshot.remove()
                self.snapshot = nil
            }
        }
    }

    func close(in window: UIWindow?, onClose: @escaping () -> Void) {
        guard let snapshot = snapshot ?? PullSnapshot(window: window) else {
            onClose()
            return
        }
        self.snapshot = snapshot
        snapshot.move(to: snapshot.height, animation: .easeOut(duration: 0.25)) {
            onClose()
            snapshot.remove()
            self.snapshot = nil
        }
    }
}

@MainActor
private final class PullSnapshot {
    private let view: UIView
    private(set) var offset: CGFloat = 0
    var height: CGFloat { view.bounds.height }

    init?(window: UIWindow?) {
        guard let window, let view = window.snapshotView(afterScreenUpdates: false) else { return nil }
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        window.addSubview(view)
        view.cornerConfiguration = .corners(radius: .containerConcentric())
        view.cornerConfiguration = .corners(radius: .fixed(view.effectiveRadius(corner: .topLeft)))
        self.view = view
    }

    func move(to offset: CGFloat, animation: Animation? = nil, completion: (() -> Void)? = nil) {
        self.offset = offset
        let changes = { self.view.transform = CGAffineTransform(translationX: 0, y: offset) }
        if let animation {
            UIView.animate(animation, changes: changes, completion: completion)
        } else {
            changes()
        }
    }

    func remove() {
        view.removeFromSuperview()
    }
}

private struct PullDown: UIGestureRecognizerRepresentable {
    let webView: UIView
    let shouldBegin: () -> Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (_ distance: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        context.coordinator.pullDown = self
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.pullDown = self
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let distance = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .changed: onChange(distance)
        case .ended: onEnd(distance, recognizer.velocity(in: recognizer.view).y)
        case .cancelled, .failed: onEnd(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var pullDown: PullDown?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let pullDown else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y > abs(velocity.x) * 2 && pullDown.shouldBegin()
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view === pullDown?.webView
        }
    }
}
