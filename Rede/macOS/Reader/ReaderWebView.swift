import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onContextMenu: ((NSMenu) -> Void)?
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
            let currentColor = highlightColor(of: hit.id)
            items = [
                HighlightColorMenuItem(selected: currentColor) { color in
                    if color != currentColor {
                        onAnnotationAction(.setColor(id: hit.id, color))
                    }
                },
                .separator(),
                ActionMenuItem(title: hasNote(hit.id) ? "查看笔记" : "添加笔记") { onAnnotationAction(.editNote(hit)) },
                ActionMenuItem(title: hasNote(hit.id) ? "移除高亮与笔记" : "移除高亮") { onAnnotationAction(.delete(id: hit.id)) },
            ]
            if menu.items.isEmpty, let onCopyHighlight {
                items.append(.separator())
                items.append(ActionMenuItem(title: "拷贝") { onCopyHighlight(hit.id) })
            }
        } else if selecting {
            items = [
                HighlightColorMenuItem(selected: nil) { color in
                    onAnnotationAction(.highlightSelection(color))
                },
                .separator(),
                ActionMenuItem(title: "添加笔记") { onAnnotationAction(.noteSelection(Settings.shared.highlightColor)) },
            ]
        } else {
            return
        }
        let trailing: [NSMenuItem] = menu.items.isEmpty ? [] : [.separator()]
        for (index, item) in (items + trailing).enumerated() {
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

private final class HighlightColorMenuItem: NSMenuItem {
    init(selected: HighlightColor?, onSelect: @escaping (HighlightColor) -> Void) {
        super.init(title: "高亮颜色", action: nil, keyEquivalent: "")
        view = HighlightColorMenuView(selected: selected, onSelect: onSelect)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class HighlightColorMenuView: NSView {
    private static let dotSize: CGFloat = 14
    private static let slotSize: CGFloat = 20
    private static let spacing: CGFloat = 2
    private static let horizontalInset: CGFloat = 12
    private static let verticalInset: CGFloat = 4

    init(selected: HighlightColor?, onSelect: @escaping (HighlightColor) -> Void) {
        let count = CGFloat(HighlightColor.allCases.count)
        let width = Self.horizontalInset * 2 + count * Self.slotSize + (count - 1) * Self.spacing
        let height = Self.verticalInset * 2 + Self.slotSize
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for (index, color) in HighlightColor.allCases.enumerated() {
            let x = Self.horizontalInset + CGFloat(index) * (Self.slotSize + Self.spacing)
            let button = HighlightSwatchControl(
                color: color,
                isSelected: color == selected,
                dotSize: Self.dotSize,
                frame: NSRect(x: x, y: Self.verticalInset, width: Self.slotSize, height: Self.slotSize)
            ) { [weak self] in
                self?.enclosingMenuItem?.menu?.cancelTracking()
                onSelect(color)
            }
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class HighlightSwatchControl: NSView {
    private let color: HighlightColor
    private let isSelected: Bool
    private let dotSize: CGFloat
    private let onClick: () -> Void
    private var isHovering = false

    init(color: HighlightColor, isSelected: Bool, dotSize: CGFloat, frame: NSRect, onClick: @escaping () -> Void) {
        self.color = color
        self.isSelected = isSelected
        self.dotSize = dotSize
        self.onClick = onClick
        super.init(frame: frame)
        toolTip = color.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(color.name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = isHovering ? dotSize + 1.5 : dotSize
        let dotRect = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor(color.swatch).setFill()
        dotPath.fill()

        if isSelected {
            let check = NSBezierPath()
            check.move(to: NSPoint(x: dotRect.minX + size * 0.28, y: dotRect.minY + size * 0.50))
            check.line(to: NSPoint(x: dotRect.minX + size * 0.44, y: dotRect.minY + size * 0.34))
            check.line(to: NSPoint(x: dotRect.minX + size * 0.73, y: dotRect.minY + size * 0.66))
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
    }
}
