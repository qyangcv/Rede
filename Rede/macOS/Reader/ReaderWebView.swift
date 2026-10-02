import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setValue(false, forKey: "drawsBackground")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

struct ReaderWebViewContainer: NSViewRepresentable {
    let reader: Reader

    func makeNSView(context: Context) -> ReaderWebView {
        reader.webView.onKeyDown = { [weak reader] event in
            reader?.handleKeyDown(event) ?? false
        }
        return reader.webView
    }

    func updateNSView(_ nsView: ReaderWebView, context: Context) {}
}

extension Reader {
    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    fileprivate func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
              let key = event.specialKey else { return false }
        switch key {
        case .leftArrow: onGesture?(.turn(.prev))
        case .rightArrow: onGesture?(.turn(.next))
        default: return false
        }
        return true
    }
}
