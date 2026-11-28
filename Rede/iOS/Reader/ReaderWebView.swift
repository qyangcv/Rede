import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import WebKit

final class ReaderWebView: WKWebView {
    var onTouchChange: ((Bool) -> Void)? {
        didSet { touchTracker.onTouchChange = onTouchChange }
    }
    var isTouching: Bool { touchTracker.isTouching }
    private let touchTracker = TouchTracker()

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        allowsLinkPreview = false
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addGestureRecognizer(touchTracker)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        builder.replaceChildren(ofMenu: .root) { _ in [] }
    }
}

private final class TouchTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouchChange: ((Bool) -> Void)?
    var isTouching: Bool { !activeTouches.isEmpty }
    private var activeTouches: Set<UITouch> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        requiresExclusiveTouchType = false
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let wasTouching = !activeTouches.isEmpty
        activeTouches.formUnion(touches)
        if !wasTouching, !activeTouches.isEmpty {
            onTouchChange?(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        end(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        end(touches)
    }

    override func reset() {
        super.reset()
        if !activeTouches.isEmpty {
            activeTouches.removeAll()
            onTouchChange?(false)
        }
    }

    private func end(_ touches: Set<UITouch>) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            state = .failed
            onTouchChange?(false)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

struct ReaderWebViewContainer: UIViewRepresentable {
    let reader: Reader

    func makeUIView(context: Context) -> ReaderWebView {
        reader.webView
    }

    func updateUIView(_ uiView: ReaderWebView, context: Context) {}
}

extension Reader {
    func focus() {}
}

struct PageRendererHost: View {
    let pages: PageRenderer

    var body: some View {
        ZStack {
            ForEach(PageDirection.allCases, id: \.self) { direction in
                if let reader = pages.readers[direction] {
                    ReaderWebViewContainer(reader: reader)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
