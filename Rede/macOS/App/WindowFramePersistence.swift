import SwiftUI

struct WindowFramePersistence: NSViewRepresentable {
    let name: NSWindow.FrameAutosaveName
    var cascading = false

    func makeNSView(context: Context) -> FrameView {
        FrameView(name: name, cascading: cascading)
    }

    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        private static var tracked: [NSWindow.FrameAutosaveName: NSHashTable<NSWindow>] = [:]

        private let name: NSWindow.FrameAutosaveName
        private let cascading: Bool
        private weak var observedWindow: NSWindow?
        private var restored = false

        init(name: NSWindow.FrameAutosaveName, cascading: Bool) {
            self.name = name
            self.cascading = cascading
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== observedWindow else { return }
            let notifications = NotificationCenter.default
            notifications.removeObserver(self)
            observedWindow = window
            restored = false
            Self.register(window, for: name)
            notifications.addObserver(self, selector: #selector(windowDidUpdate),
                                      name: NSWindow.didUpdateNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowWillClose),
                                      name: NSWindow.willCloseNotification, object: window)
            notifications.addObserver(self, selector: #selector(applicationWillTerminate),
                                      name: NSApplication.willTerminateNotification, object: NSApp)
            restoreFrameWhenVisible()
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            restoreFrameWhenVisible()
        }

        private func restoreFrameWhenVisible() {
            guard !restored, let window = observedWindow, window.isVisible else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.observedWindow === window, window.isVisible, !self.restored else { return }
                self.restored = true
                window.setFrameUsingName(self.name)
                if self.cascading, let anchor = Self.frontmostVisible(named: self.name, excluding: window) {
                    let topLeft = anchor.cascadeTopLeft(from: .zero)
                    window.cascadeTopLeft(from: topLeft)
                }
            }
        }

        @objc private func windowWillClose(_ notification: Notification) {
            saveFrame()
            restored = false
        }

        @objc private func applicationWillTerminate(_ notification: Notification) {
            saveFrame()
        }

        private func saveFrame() {
            guard restored else { return }
            observedWindow?.saveFrame(usingName: name)
        }

        private static func register(_ window: NSWindow, for name: NSWindow.FrameAutosaveName) {
            let table = tracked[name] ?? .weakObjects()
            table.add(window)
            tracked[name] = table
        }

        private static func frontmostVisible(named name: NSWindow.FrameAutosaveName,
                                             excluding window: NSWindow) -> NSWindow? {
            guard let table = tracked[name] else { return nil }
            return NSApp.orderedWindows.first { candidate in
                candidate !== window && candidate.isVisible && table.contains(candidate)
            }
        }
    }
}
