import Foundation
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct RenderedPage {
    let image: PlatformImage
    let position: ReadingPosition
    let page: PageInfo
    let chapter: TOCItem?
}

final class PageRenderer {
    private static let depth = 3

    let readers: [PageDirection: Reader]
    var onCurrent: ((RenderedPage) -> Void)?
    private var window: [RenderedPage] = []
    private var center = 0
    private var rendering: Set<PageDirection> = []
    private let main: Reader
    private var ready: Set<PageDirection> = []
    private var generation = 0

    var anchor: RenderedPage? {
        window.indices.contains(center) ? window[center] : nil
    }

    init(main: Reader, book: EpubBook, start: ReadingPosition?) {
        self.main = main
        readers = Dictionary(uniqueKeysWithValues: PageDirection.allCases.map {
            ($0, Reader(book: book, start: start))
        })
        for (direction, reader) in readers {
            reader.onProgress = { [weak self] _, _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.ready.insert(direction).inserted else { return }
                    self.fill(direction)
                }
            }
        }
    }

    func open(style: [String: String]) {
        for reader in readers.values { reader.open(style: style) }
    }

    func apply(_ style: [String: String]) {
        invalidate()
        for reader in readers.values { reader.apply(style) }
    }

    func invalidate() {
        generation += 1
        window = []
        center = 0
    }

    func prepare(_ position: ReadingPosition, page: PageInfo, chapter: TOCItem?) {
        guard index(of: position) == nil else { return }
        invalidate()
        let generation = generation
        Task {
            guard let image = await main.snapshot(), generation == self.generation else { return }
            let current = RenderedPage(image: image, position: position, page: page, chapter: chapter)
            window = [current]
            onCurrent?(current)
            for direction in PageDirection.allCases { fill(direction) }
        }
    }

    func neighbor(of page: RenderedPage, _ direction: PageDirection) -> RenderedPage? {
        guard let i = index(of: page.position) else { return nil }
        let j = i + direction.step
        return window.indices.contains(j) ? window[j] : nil
    }

    func move(to page: RenderedPage) {
        guard let i = index(of: page.position) else { return }
        let lower = max(0, i - Self.depth)
        window = Array(window[lower..<min(window.count, i + Self.depth + 1)])
        center = i - lower
        for direction in PageDirection.allCases { fill(direction) }
    }

    private func index(of position: ReadingPosition) -> Int? {
        window.firstIndex { $0.position == position }
    }

    private func fill(_ direction: PageDirection) {
        guard ready.contains(direction), !rendering.contains(direction), !window.isEmpty,
              let reader = readers[direction] else { return }
        let count = direction == .next ? window.count - 1 - center : center
        guard count < Self.depth, let from = direction == .next ? window.last : window.first else { return }
        let generation = generation
        rendering.insert(direction)
        Task {
            let page = await reader.peek(from: from.position, step: direction.step)
            rendering.remove(direction)
            let end = direction == .next ? window.last : window.first
            let valid = generation == self.generation && end?.position == from.position
            if valid, let page {
                if direction == .next {
                    window.append(page)
                } else {
                    window.insert(page, at: 0)
                    center += 1
                }
            }
            if !valid || page != nil { fill(direction) }
        }
    }
}
