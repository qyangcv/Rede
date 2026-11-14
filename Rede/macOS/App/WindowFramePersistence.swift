import SwiftUI

struct WindowFramePersistence: NSViewRepresentable {
    let name: NSWindow.FrameAutosaveName

    func makeNSView(context: Context) -> FrameView {
        FrameView(name: name)
    }

    func updateNSView(_ nsView: FrameView, context: Context) {}

    final class FrameView: NSView {
        private let name: NSWindow.FrameAutosaveName
        private weak var observedWindow: NSWindow?
        private var restored = false

        init(name: NSWindow.FrameAutosaveName) {
            self.name = name
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
    }
}
