import SwiftUI
import UIKit

@Observable
final class PageCurl: NSObject, PageTurner, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private(set) var turning = false

    @ObservationIgnored private weak var controller: UIPageViewController?
    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let renderer: PageRenderer
    @ObservationIgnored private var gestures: [UIGestureRecognizer] = []
    @ObservationIgnored private var curling = 0
    @ObservationIgnored private var following: Task<Void, Never>?

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
        if let page = renderer.anchor {
            controller.setViewControllers([PageController(page)], direction: .forward, animated: false)
        }
        self.controller = controller
        return controller
    }

    func turn(_ direction: PageDirection) {
        guard let controller, let anchor = renderer.anchor,
              let page = renderer.neighbor(of: anchor, direction) else { return }
        renderer.move(to: page)
        begin()
        follow(page)
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
            guard curling == 0, renderer.anchor?.position == page.position else { return }
            show(page)
        }
    }

    private func receive(_ page: RenderedPage) {
        guard curling == 0 else { return }
        show(page)
    }

    private func show(_ page: RenderedPage) {
        controller?.setViewControllers([PageController(page)], direction: .forward, animated: false)
        turning = false
    }

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

struct PageDecor: View {
    let chapter: TOCItem?
    let page: PageInfo?

    var body: some View {
        ZStack {
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
