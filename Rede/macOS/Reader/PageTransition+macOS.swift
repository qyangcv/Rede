import SwiftUI

extension PageTransition {
    func makeTurner(reader: Reader) -> any PageTurner {
        switch self {
        case .none: SwipePageTurner(reader: reader)
        }
    }
}

@Observable
final class SwipePageTurner: PageTurner {
    struct Slide {
        let current: RenderedPage
        let target: RenderedPage
        let direction: PageDirection
        var progress: CGFloat = 0
    }

    private(set) var slide: Slide?
    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let renderer: PageRenderer
    @ObservationIgnored private var navigation: Task<Void, Never>?
    @ObservationIgnored private var queuedTurns: [PageDirection] = []

    init(reader: Reader) {
        self.reader = reader
        renderer = PageRenderer(main: reader, followsMain: true)
        renderer.onInvalidate = { [weak self] in
            guard let self, self.navigation == nil else { return }
            self.slide = nil
        }
        reader.webView.swipeTurner = self
    }

    var pages: PageRenderer? { renderer }
    var layer: AnyView { AnyView(SwipePageLayer(turner: self)) }

    func beginSwipe(_ direction: PageDirection) -> Bool {
        guard navigation == nil, !reader.selecting, let current = renderer.anchor,
              current.position == reader.position,
              let target = renderer.neighbor(of: current, direction) else { return false }
        slide = Slide(current: current, target: target, direction: direction)
        return true
    }

    func updateSwipe(_ progress: CGFloat, complete: Bool) {
        guard let slide, navigation == nil else { return }
        guard reader.position == slide.current.position, !reader.selecting else {
            self.slide = nil
            return
        }

        if !complete {
            self.slide?.progress = progress
        } else if progress == 1 {
            self.slide?.progress = 1
            navigate(to: slide.target.position)
        } else {
            self.slide = nil
        }
    }

    func turn(_ direction: PageDirection) {
        queuedTurns.append(direction)
        guard navigation == nil else { return }
        slide = nil
        navigate()
    }

    func detach() {
        navigation?.cancel()
        navigation = nil
        queuedTurns.removeAll()
        slide = nil
        if reader.webView.swipeTurner === self { reader.webView.swipeTurner = nil }
    }

    private func navigate(to position: ReadingPosition? = nil) {
        let reader = reader
        navigation = Task { [weak self] in
            if let position { await reader.show(position) }
            guard !Task.isCancelled else { return }
            self?.slide = nil
            while let direction = self?.queuedTurns.first {
                self?.queuedTurns.removeFirst()
                await reader.turn(direction.step).value
                guard !Task.isCancelled else { return }
            }
            self?.navigation = nil
        }
    }
}

private struct SwipePageLayer: View {
    let turner: SwipePageTurner

    var body: some View {
        GeometryReader { proxy in
            if let slide = turner.slide {
                let distance = proxy.size.width * CGFloat(slide.direction.step)
                ZStack {
                    page(slide.current, size: proxy.size)
                        .offset(x: -slide.progress * distance)
                    page(slide.target, size: proxy.size)
                        .offset(x: (1 - slide.progress) * distance)
                }
                .clipped()
            }
        }
        .transaction { $0.animation = nil }
    }

    private func page(_ page: RenderedPage, size: CGSize) -> some View {
        Image(nsImage: page.image)
            .resizable()
            .frame(width: size.width, height: size.height)
    }
}
