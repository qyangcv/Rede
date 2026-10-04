import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onContextMenu: ((NSMenu) -> Void)?

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

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        onContextMenu?(menu)
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
        reader.webView.onContextMenu = { [weak reader] menu in reader?.extendMenu(menu) }
        return reader.webView
    }

    func updateNSView(_ nsView: ReaderWebView, context: Context) {}
}

extension Reader {
    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    fileprivate func extendMenu(_ menu: NSMenu) {
        guard let onAnnotationAction else { return }
        let items: [NSMenuItem]
        if let hit = contextHighlight {
            items = [
                ActionMenuItem(title: hasNote(hit.id) ? "编辑笔记…" : "添加笔记…") { onAnnotationAction(.editNote(hit)) },
                ActionMenuItem(title: "删除高亮") { onAnnotationAction(.delete(id: hit.id)) },
            ]
        } else if selecting {
            items = [
                ActionMenuItem(title: "高亮") { onAnnotationAction(.highlightSelection) },
                ActionMenuItem(title: "添加笔记…") { onAnnotationAction(.noteSelection) },
            ]
        } else {
            return
        }
        for (index, item) in (items + [.separator()]).enumerated() {
            menu.insertItem(item, at: index)
        }
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
