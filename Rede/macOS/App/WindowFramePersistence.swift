import SwiftUI

struct WindowFramePersistence: NSViewRepresentable {
    let name: NSWindow.FrameAutosaveName
    var cascading = false

    static func placement(
        for name: NSWindow.FrameAutosaveName,
        cascading: Bool = false,
        in context: WindowPlacementContext,
        fallback: () -> WindowPlacement
    ) -> WindowPlacement {
        let saved = FrameView.loadSavedFrame(for: name)
        let anchor = cascading ? FrameView.frontmostVisible(named: name) : nil
        var target: NSRect

        if let saved {
            target = FrameView.fittedFrame(saved, fallback: anchor?.screen ?? NSScreen.main)
        } else if let anchor {
            target = FrameView.fittedFrame(anchor.frame, fallback: anchor.screen)
        } else {
            return fallback()
        }

        if cascading {
            target = FrameView.cascadedFrame(from: target, for: name, fallback: anchor?.screen ?? NSScreen.main)
            FrameView.recordPendingPlacement(target, for: name)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? context.defaultDisplay.bounds.height
        let position = CGPoint(x: target.minX, y: primaryHeight - target.maxY)
        return WindowPlacement(position, size: target.size)
    }

    func makeNSView(context: Context) -> FrameView {
        FrameView(name: name, cascading: cascading)
    }

    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        private static let cascadeStep: CGFloat = 29
        private static var tracked: [NSWindow.FrameAutosaveName: NSHashTable<NSWindow>] = [:]
        private static var lastActive: [NSWindow.FrameAutosaveName: ObjectIdentifier] = [:]
        private static var pendingPlacements: [NSWindow.FrameAutosaveName: [NSRect]] = [:]

        private let name: NSWindow.FrameAutosaveName
        private let cascading: Bool
        private weak var observedWindow: NSWindow?
        private var hasAppeared = false
        private var isTransitioningFullScreen = false

        init(name: NSWindow.FrameAutosaveName, cascading: Bool) {
            self.name = name
            self.cascading = cascading
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            let notifications = NotificationCenter.default
            notifications.removeObserver(self)
            observedWindow = window
            hasAppeared = window.isVisible
            isTransitioningFullScreen = false
            Self.register(window, for: name)
            notifications.addObserver(self, selector: #selector(windowDidUpdate),
                                      name: NSWindow.didUpdateNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowDidBecomeKey),
                                      name: NSWindow.didBecomeKeyNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowDidMoveOrResize),
                                      name: NSWindow.didMoveNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowDidMoveOrResize),
                                      name: NSWindow.didResizeNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowWillEnterFullScreen),
                                      name: NSWindow.willEnterFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowDidEnterFullScreen),
                                      name: NSWindow.didEnterFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowWillExitFullScreen),
                                      name: NSWindow.willExitFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowDidExitFullScreen),
                                      name: NSWindow.didExitFullScreenNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowWillClose),
                                      name: NSWindow.willCloseNotification, object: window)
            notifications.addObserver(self, selector: #selector(applicationWillTerminate),
                                      name: NSApplication.willTerminateNotification, object: NSApp)
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            if !hasAppeared, observedWindow?.isVisible == true {
                hasAppeared = true
            }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            guard let window = observedWindow else { return }
            hasAppeared = true
            Self.lastActive[name] = ObjectIdentifier(window)
        }

        @objc private func windowDidMoveOrResize(_ notification: Notification) {
            guard let window = observedWindow, window.isVisible else { return }
            hasAppeared = true
            Self.lastActive[name] = ObjectIdentifier(window)
            saveFrame()
        }

        @objc private func windowWillEnterFullScreen(_ notification: Notification) {
            saveFrame()
            isTransitioningFullScreen = true
        }

        @objc private func windowDidEnterFullScreen(_ notification: Notification) {
            isTransitioningFullScreen = false
        }

        @objc private func windowWillExitFullScreen(_ notification: Notification) {
            isTransitioningFullScreen = true
        }

        @objc private func windowDidExitFullScreen(_ notification: Notification) {
            isTransitioningFullScreen = false
        }

        @objc private func windowWillClose(_ notification: Notification) {
            saveFrame()
            if let window = observedWindow, Self.lastActive[name] == ObjectIdentifier(window) {
                Self.lastActive[name] = nil
            }
            hasAppeared = false
        }

        @objc private func applicationWillTerminate(_ notification: Notification) {
            guard let window = observedWindow else { return }
            if !cascading || Self.lastActive[name] == ObjectIdentifier(window) || Self.lastActive[name] == nil {
                saveFrame()
            }
        }

        private func saveFrame() {
            guard hasAppeared, !isTransitioningFullScreen,
                  let window = observedWindow,
                  !window.styleMask.contains(.fullScreen) else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.defaultsKey(for: name))
        }

        static func defaultsKey(for name: NSWindow.FrameAutosaveName) -> String {
            "WindowFrame.\(name)"
        }

        static func loadSavedFrame(for name: NSWindow.FrameAutosaveName) -> NSRect? {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey(for: name)) else { return nil }
            let rect = NSRectFromString(raw)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return rect
        }

        static func fittedFrame(_ frame: NSRect, fallback: NSScreen?) -> NSRect {
            guard let screen = targetScreen(for: frame, fallback: fallback) else { return frame }
            let visible = screen.visibleFrame
            let width = min(frame.width, visible.width)
            let height = min(frame.height, visible.height)
            let x = min(max(frame.minX, visible.minX), visible.maxX - width)
            let y = min(max(frame.minY, visible.minY), visible.maxY - height)
            return NSRect(x: x, y: y, width: width, height: height)
        }

        private static func targetScreen(for frame: NSRect, fallback: NSScreen?) -> NSScreen? {
            let best = NSScreen.screens.max { a, b in
                intersectionArea(frame, a.visibleFrame) < intersectionArea(frame, b.visibleFrame)
            }
            if let best, intersectionArea(frame, best.visibleFrame) > 0 {
                return best
            }
            return fallback ?? NSScreen.main ?? NSScreen.screens.first
        }

        private static func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
            let rect = a.intersection(b)
            guard !rect.isNull, !rect.isEmpty else { return 0 }
            return rect.width * rect.height
        }

        private static func register(_ window: NSWindow, for name: NSWindow.FrameAutosaveName) {
            let table = tracked[name] ?? .weakObjects()
            table.add(window)
            tracked[name] = table
        }

        static func frontmostVisible(named name: NSWindow.FrameAutosaveName) -> NSWindow? {
            guard let table = tracked[name] else { return nil }
            return NSApp.orderedWindows.first { candidate in
                candidate.isVisible && !candidate.styleMask.contains(.fullScreen) && table.contains(candidate)
            }
        }

        static func recordPendingPlacement(_ rect: NSRect, for name: NSWindow.FrameAutosaveName) {
            pendingPlacements[name, default: []].append(rect)
            DispatchQueue.main.async {
                pendingPlacements[name]?.removeAll()
            }
        }

        static func cascadedFrame(from base: NSRect, for name: NSWindow.FrameAutosaveName, fallback: NSScreen?) -> NSRect {
            let visibleFrames = (tracked[name]?.allObjects ?? [])
                .filter { $0.isVisible && !$0.styleMask.contains(.fullScreen) }
                .map(\.frame)
            let occupied = visibleFrames + (pendingPlacements[name] ?? [])
            guard !occupied.isEmpty else { return base }

            let screenVisible = targetScreen(for: base, fallback: fallback)?.visibleFrame
            var candidate = base
            for _ in 0..<20 {
                let collides = occupied.contains {
                    abs($0.minX - candidate.minX) < 2 && abs($0.maxY - candidate.maxY) < 2
                }
                if !collides { break }
                candidate.origin.x += cascadeStep
                candidate.origin.y -= cascadeStep
                if let visible = screenVisible {
                    if candidate.maxX > visible.maxX {
                        candidate.origin.x = visible.minX
                    }
                    if candidate.minY < visible.minY {
                        candidate.origin.y = visible.maxY - candidate.height
                    }
                }
            }
            return fittedFrame(candidate, fallback: fallback)
        }
    }
}
