import SwiftUI

struct ReaderScreen: View {
    private static let edge = 0.3

    private enum Panel: Identifiable {
        case toc, style
        var id: Self { self }
    }

    private static let pullDistance: CGFloat = 120
    private static let pullVelocity: CGFloat = 800

    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    @State private var chromeVisible = false
    @State private var panel: Panel?
    @State private var styleHeight: CGFloat?
    @State private var snapshot: PullSnapshot?

    var body: some View {
        if let reader = session.reader, let turner = session.turner {
            ReaderView(reader: reader, pages: turner.pages, page: nil)
                .gesture(PullDown(webView: reader.webView,
                                  shouldBegin: { panel == nil && !reader.selecting },
                                  onChange: { pulling($0, reader: reader) },
                                  onEnd: { pulled($0, velocity: $1) }))
                .overlay {
                    PageDecor(chapter: chromeVisible ? nil : session.chapter, page: session.page)
                }
                .overlay {
                    turner.layer
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .background {
                    if let pages = turner.pages {
                        PageRendererHost(pages: pages)
                    }
                }
                .overlay {
                    if chromeVisible {
                        chrome.transition(.opacity)
                    }
                }
                .overlay { dimmer }
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                .background {
                    settings.readerStyle.background.swatch(for: colorScheme)
                        .ignoresSafeArea()
                }
                .opacity(snapshot == nil ? 1 : 0)
                .presentationBackground(.clear)
                .statusBarHidden(!chromeVisible)
                .sheet(item: $panel) { item in
                    sheet(item, reader: reader)
                        .presentationBackground(ChromeStyle(background: settings.readerStyle.background, level: .panel))
                        .overlay { dimmer }
                }
                .onAppear {
                    reader.onGesture = { handle($0) }
                    reader.onTurn = {
                        chromeVisible = false
                        panel = nil
                    }
                }
                .onChange(of: settings.pageTransition) { _, new in session.setTransition(new) }
                .id(ObjectIdentifier(reader))
        }
    }

    private var chrome: some View {
        VStack {
            Button { close() } label: {
                Label("关闭", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: CGFloat(ReaderLayout.marginTop))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer()

            bottomBar
        }
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barItem("目录", systemImage: "list.bullet") { panel = .toc }
            Divider().frame(height: 20)
            barItem("样式", systemImage: "textformat") {
                chromeVisible = false
                panel = .style
            }
        }
        .buttonStyle(.plain)
        .barBackground(in: .capsule, background: settings.readerStyle.background)
    }

    private func barItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .environment(\.locale, Locale(identifier: "en"))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
        }
    }

    private var dimmer: some View {
        Color.black.opacity(1 - pow(settings.brightness, 1 / 2.2))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sheet(_ item: Panel, reader: Reader) -> some View {
        switch item {
        case .toc:
            TOCList(items: reader.toc, current: session.chapter?.id) { entry in
                panel = nil
                reader.go(to: entry)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .style:
            StyleSheet(style: $settings.readerStyle, appearance: $settings.appearance,
                       transition: $settings.pageTransition, brightness: $settings.brightness)
                .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.bottom } action: { styleHeight = $0 }
                .presentationDetents([styleHeight.map { .height($0) } ?? .medium])
                .presentationBackgroundInteraction(.enabled)
        }
    }

    private func handle(_ gesture: ReaderGesture) {
        switch gesture {
        case .tap(let x):
            if chromeVisible { chromeVisible = false }
            else if x < Self.edge { session.turner?.turn(.prev) }
            else if x > 1 - Self.edge { session.turner?.turn(.next) }
            else if panel != nil { panel = nil }
            else { chromeVisible = true }
        case .turn(let direction):
            session.turner?.turn(direction)
        }
    }

    private func pulling(_ distance: CGFloat, reader: Reader) {
        if snapshot == nil { snapshot = PullSnapshot(window: reader.webView.window) }
        snapshot?.move(to: max(0, distance))
    }

    private func pulled(_ distance: CGFloat, velocity: CGFloat) {
        if distance > Self.pullDistance || velocity > Self.pullVelocity {
            close()
        } else if let snapshot {
            snapshot.move(to: 0, animation: .spring) {
                guard snapshot.offset == 0 else { return }
                snapshot.remove()
                self.snapshot = nil
            }
        }
    }

    private func close() {
        guard let snapshot = snapshot ?? PullSnapshot(window: session.reader?.webView.window) else {
            session.close()
            return
        }
        self.snapshot = snapshot
        snapshot.move(to: snapshot.height, animation: .easeOut(duration: 0.25)) {
            session.close()
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

private extension View {
    func barBackground(in shape: some Shape, background: BackgroundColor) -> some View {
        self.background(ChromeStyle(background: background, level: .card), in: shape)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
