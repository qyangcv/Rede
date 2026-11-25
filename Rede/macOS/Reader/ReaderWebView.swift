import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onContextMenu: ((NSMenu) -> Void)?
    var onCopy: (() -> Bool)?
    weak var swipeTurner: SwipePageTurner?

    private var trackingSwipe = false

    private static let copyMenuItemIdentifier = "WKMenuItemIdentifierCopy"

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setValue(false, forKey: "drawsBackground")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")
    }

    private var toolbarObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard onKeyDown != nil else { return }
        window?.makeFirstResponder(self)
        toolbarObservation = window?.observe(\.toolbar, options: [.initial, .new]) { window, _ in
            window.toolbar?.allowsDisplayModeCustomization = false
        }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where item.identifier?.rawValue != Self.copyMenuItemIdentifier {
            menu.removeItem(item)
        }
        onContextMenu?(menu)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        nil
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           onCopy?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if trackingSwipe { return }
        guard event.phase == .began, event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            super.scrollWheel(with: event)
            return
        }
        let direction: PageDirection = event.scrollingDeltaX < 0 ? .next : .prev
        guard let swipeTurner, swipeTurner.beginSwipe(direction) else {
            super.scrollWheel(with: event)
            return
        }

        trackingSwipe = true
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: -1, max: 1) { [weak self, weak swipeTurner] amount, _, complete, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            if complete { self.trackingSwipe = false }
            swipeTurner?.updateSwipe(abs(amount), complete: complete)
        }
    }
}

struct ReaderWebViewContainer: NSViewRepresentable {
    let reader: Reader

    func makeNSView(context: Context) -> ReaderWebView {
        reader.webView.onKeyDown = { [weak reader] event in
            reader?.handleKeyDown(event) ?? false
        }
        reader.webView.onContextMenu = { [weak reader] menu in reader?.extendMenu(menu) }
        reader.webView.onCopy = { [weak reader] in reader?.copyActiveHighlight() ?? false }
        return reader.webView
    }

    func updateNSView(_ nsView: ReaderWebView, context: Context) {}
}

struct PageRendererHost: NSViewRepresentable {
    let pages: PageRenderer

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        for reader in pages.readers.values {
            let webView = reader.webView
            webView.frame = host.bounds
            webView.autoresizingMask = [.width, .height]
            host.addSubview(webView)
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension Reader {
    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    fileprivate func extendMenu(_ menu: NSMenu) {
        guard let onAnnotationAction else { return }
        var items: [NSMenuItem]
        if let hit = contextHighlight {
            items = [
                ActionMenuItem(title: hasNote(hit.id) ? "查看笔记" : "添加笔记") { onAnnotationAction(.editNote(hit)) },
                ActionMenuItem(title: hasNote(hit.id) ? "移除高亮与笔记" : "移除高亮") { onAnnotationAction(.delete(id: hit.id)) },
            ]
            if menu.items.isEmpty, let onCopyHighlight {
                items.append(.separator())
                items.append(ActionMenuItem(title: "拷贝") { onCopyHighlight(hit.id) })
            }
        } else if selecting {
            items = [
                ActionMenuItem(title: "高亮") { onAnnotationAction(.highlightSelection) },
                ActionMenuItem(title: "添加笔记") { onAnnotationAction(.noteSelection) },
            ]
        } else {
            return
        }
        let trailing: [NSMenuItem] = menu.items.isEmpty ? [] : [.separator()]
        for (index, item) in (items + trailing).enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    fileprivate func copyActiveHighlight() -> Bool {
        guard !selecting, let id = activeHighlightID, let onCopyHighlight else { return false }
        onCopyHighlight(id)
        return true
    }

    fileprivate func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]) else { return false }
        if event.keyCode == 53, activeHighlightID != nil {
            clearActiveHighlight()
            return true
        }
        guard let key = event.specialKey else { return false }
        switch key {
        case .leftArrow: onGesture?(.turn(.prev))
        case .rightArrow: onGesture?(.turn(.next))
        default: return false
        }
        return true
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() {
        handler()
    }
}
