import SwiftUI
import UIKit

// 仿真翻页：UIPageViewController 的每一页都是截图（加上章节名、页码），盖在活的 WebView 上，只在翻页时显示。
// 卷页层不接收触摸，触摸始终落在 WebView 上：PageVC 的拖动手势挂在 WebView 上，
// 点按翻页由 reader.js 识别后调 turn(_:)，翻页过程中也能接着翻。
// 连续快速翻页时多个卷页动画叠在一起；每翻一页主 WebView 立即跟过去，全部停下且它画好后撤掉卷页层。
@Observable
final class PageCurl: NSObject, PageTurner, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    // 为 true 时显示卷页层
    private(set) var turning = false

    @ObservationIgnored private weak var controller: UIPageViewController?
    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let renderer: PageRenderer
    // 从 PageVC 搬到主 WebView 上的拖动手势，detach() 时撤掉
    @ObservationIgnored private var gestures: [UIGestureRecognizer] = []
    // 正在播放的卷页动画数
    @ObservationIgnored private var curling = 0
    // 主 WebView 跟到最近一次翻到的页
    @ObservationIgnored private var following: Task<Void, Never>?

    // 相邻页从主 Reader 当前所在的位置开始渲染：打开书时是保存的进度，阅读中切换过来时是当前页
    init(reader: Reader) {
        self.reader = reader
        renderer = PageRenderer(main: reader, book: reader.book, start: reader.position)
        super.init()
        renderer.onCurrent = { [weak self] page in self?.receive(page) }
    }

    var pages: PageRenderer? { renderer }
    var layer: AnyView { AnyView(PageCurlLayer(curl: self)) }

    func detach() {
        gestures.forEach { reader.webView.removeGestureRecognizer($0) }
        gestures = []
    }

    fileprivate func makeController() -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        // 双面：卷起那页的背面由 PageView 自己画，否则系统会把正面镜像后半透明地叠在下一页上
        controller.isDoubleSided = true
        controller.dataSource = self
        controller.delegate = self
        for recognizer in controller.gestureRecognizers {
            if recognizer is UITapGestureRecognizer {
                recognizer.isEnabled = false
            } else {
                reader.webView.addGestureRecognizer(recognizer)
                gestures.append(recognizer)
            }
        }
        // 卷页层挂上之前窗口可能已经建好，receive(_:) 那时还没有 controller
        if let page = renderer.anchor {
            controller.setViewControllers([PageController(page)], direction: .forward, animated: false)
        }
        self.controller = controller
        return controller
    }

    // 点按翻页；这一侧还没渲染好（或到书头书尾）时不翻
    func turn(_ direction: PageDirection) {
        guard let controller, let anchor = renderer.anchor,
              let page = renderer.neighbor(of: anchor, direction) else { return }
        renderer.move(to: page)
        begin()
        follow(page)
        // 双面时带动画翻页要给正反两面，不带动画的 show(_:) 只给正面
        controller.setViewControllers([PageController(page), PageController(page, isBack: true)],
                                      direction: direction == .next ? .forward : .reverse,
                                      animated: true) { [weak self] _ in
            self?.end()
        }
    }

    private func begin() {
        curling += 1
        turning = true
    }

    private func follow(_ page: RenderedPage) {
        following = Task { await reader.show(page.position) }
    }

    private func end() {
        curling -= 1
        guard curling == 0, let page = renderer.anchor else { return }
        let following = following
        Task {
            await following?.value
            // 等待期间又开始翻页，或窗口已围绕别处重建：交给之后的 end() 或 receive(_:)
            guard curling == 0, renderer.anchor?.position == page.position else { return }
            show(page)
        }
    }

    // 主 Reader 跳到别处（打开、目录跳转、重排）后，窗口重建出的中心页；卷页中途到达的由 end() 收尾
    private func receive(_ page: RenderedPage) {
        guard curling == 0 else { return }
        show(page)
    }

    private func show(_ page: RenderedPage) {
        controller?.setViewControllers([PageController(page)], direction: .forward, animated: false)
        turning = false
    }

    // 双面时页序是：前一页正面、前一页背面、当前页正面、当前页背面、后一页正面。
    // 按传入的那一面找相邻页：连续快速滑动时，上一次卷页还没结束，这里问的可能已经是它翻到的页
    private func neighbor(of viewController: UIViewController,
                          _ direction: PageDirection) -> UIViewController? {
        guard let side = viewController as? PageController,
              let page = renderer.neighbor(of: side.page, direction) else { return nil }
        return switch (direction, side.isBack) {
        case (.next, false): PageController(side.page, isBack: true)
        case (.next, true): PageController(page)
        case (.prev, false): PageController(page, isBack: true)
        case (.prev, true): PageController(side.page)
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        neighbor(of: viewController, .prev)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        neighbor(of: viewController, .next)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        begin()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let page = (pageViewController.viewControllers?.first as? PageController)?.page {
            renderer.move(to: page)
            follow(page)
        }
        end()
    }
}

// 卷页层只在翻页时显示；turning 在这里读，翻页时只重绘这一层
private struct PageCurlLayer: View {
    let curl: PageCurl

    var body: some View {
        PageCurlView(curl: curl)
            .opacity(curl.turning ? 1 : 0)
    }
}

private struct PageCurlView: UIViewControllerRepresentable {
    let curl: PageCurl

    func makeUIViewController(context: Context) -> UIPageViewController {
        curl.makeController()
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {}
}

// 章节名和页码：活的 WebView 上和截图页上共用，保证卷页时位置一致
struct PageDecor: View {
    let chapter: TOCItem?
    let page: PageInfo?

    var body: some View {
        ZStack {
            // 完整层级路径，放不下时截掉前面的上级，保证当前章节可见；在安全区内避开灵动岛，与正文左边缘对齐
            if let chapter {
                Text(chapter.path.map(\.title).joined(separator: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, CGFloat(ReaderLayout.gutter))
                    .padding(.top, ReaderLayout.chapterTitleTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let page {
                Text("\(page.page + 1) / \(page.pageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.bottom, ReaderLayout.pageNumberBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PageView: View {
    let page: RenderedPage
    let isBack: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Image(uiImage: page.image)
                .resizable()
                .scaleEffect(x: isBack ? -1 : 1)
                .ignoresSafeArea()
            if isBack {
                // 背面：正面内容镜像后隐约透出，像纸背
                Settings.shared.readerStyle.background.swatch(for: colorScheme)
                    .opacity(0.85)
                    .ignoresSafeArea()
            } else {
                PageDecor(chapter: page.chapter, page: page.page)
            }
        }
    }
}

private final class PageController: UIHostingController<PageView> {
    var page: RenderedPage { rootView.page }
    var isBack: Bool { rootView.isBack }

    init(_ page: RenderedPage, isBack: Bool = false) {
        super.init(rootView: PageView(page: page, isBack: isBack))
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
