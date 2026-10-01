import SwiftUI

struct ReaderScreen: View {
    // 左右两侧各占宽度的 30%，点击翻页；中间点击显示工具栏
    private static let edge = 0.3

    private enum Panel: Identifiable {
        case toc, style
        var id: Self { self }
    }

    // 下滑超过这个距离，或松手时向下的速度超过这个值，关闭书本
    private static let pullDistance: CGFloat = 120
    private static let pullVelocity: CGFloat = 800

    @Environment(ReaderSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared
    @State private var chromeVisible = false
    @State private var panel: Panel?
    @State private var styleHeight: CGFloat?
    // 下滑关闭时跟手移动的截图，松手弹回或关闭后撤掉
    @State private var snapshot: PullSnapshot?

    var body: some View {
        if let reader = session.reader, let turner = session.turner {
            // 从下往上：相邻页渲染器、活的 WebView、翻页动画层；动画层不接收触摸
            // 工具栏是浮在正文上的覆盖层，不占安全区：显示或隐藏它不会改变 WebView 的尺寸和安全区，不触发 reflow
            ReaderView(reader: reader, pages: turner.pages, page: nil)
                // 面板打开时正文仍可交互，用来对照调整样式，这时不响应下滑
                .gesture(PullDown(webView: reader.webView,
                                  shouldBegin: { panel == nil && !reader.selecting },
                                  onChange: { pulling($0, reader: reader) },
                                  onEnd: { pulled($0, velocity: $1) }))
                // 章节名和页码与截图页共用 PageDecor；工具栏出现时章节名让位给关闭按钮
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
                .animation(.easeInOut(duration: 0.2), value: chromeVisible)
                // 全屏弹出层背景透明，下拉时露出书库；页面自己垫上底色，网页加载前也不透出书库
                .background {
                    settings.readerStyle.background.swatch(for: colorScheme)
                        .ignoresSafeArea()
                }
                // 下拉时阅读页原地不动并隐藏，由盖在窗口上的截图跟手移动
                .opacity(snapshot == nil ? 1 : 0)
                .presentationBackground(.clear)
                .statusBarHidden(!chromeVisible)
                // 面板从这里弹出而不是从按钮上：工具栏的按钮样式不会传进面板
                .sheet(item: $panel) { item in
                    sheet(item, reader: reader)
                        .presentationBackground(.background)
                }
                .onAppear {
                    reader.onGesture = { handle($0) }
                    // 翻页即回到阅读，收起工具栏和面板
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
            // 向下的箭头放在顶部中间，提示整页可以往下拉走
            Button("关闭", systemImage: "chevron.down") { close() }

            Spacer()

            HStack {
                Button("目录", systemImage: "list.bullet") { panel = .toc }
                Spacer()
                // 面板要对照正文调整，打开时收起工具栏，不遮挡正文顶部
                Button("样式", systemImage: "textformat") {
                    chromeVisible = false
                    panel = .style
                }
                    .environment(\.locale, Locale(identifier: "en"))
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding(.horizontal, 20)
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
            // 高度贴合面板内容，上方露出正文；正文不压暗且可点击，调整时能看到实时效果
            StyleSheet(style: $settings.readerStyle, appearance: $settings.appearance,
                       transition: $settings.pageTransition)
                // sheet 会在 detent 高度外再加底部安全区，这里先减掉
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
                // 弹回途中又开始下拉时，截图继续留用
                guard snapshot.offset == 0 else { return }
                snapshot.remove()
                self.snapshot = nil
            }
        }
    }

    // 截图滑出屏幕后再关闭：关闭后正文立即清空，弹出层自带的退场动画只剩透明背景，看不出来
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

// 下滑关闭时跟手移动的屏幕截图，盖在窗口最上层。
// 不直接移动阅读页：SwiftUI 会按移动后的位置重算安全区，正文、章节名、页码随拖动重排
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
        // 圆角取刚放上去时与屏幕同心的值，即屏幕圆角，起手时看不出变化；
        // 之后固定下来，不随下移重算
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

// 下滑关闭书本。手势挂在正文上，只在明显向下拖动时开始。
// 主 WebView 上的翻页手势（左右轻扫、卷页拖动）要等它失败；横向起手时它立即失败，翻页不受影响
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
