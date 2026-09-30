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

// 翻页动画用的截图窗口：按阅读顺序排列，中心是卷页层当前显示的页，前后各备 depth 页。
// 中心页最初截自主 WebView；两侧由两个不可见的 Reader 各自朝一个方向从最远那页往外续写。
// 翻页只是移动中心：翻过去的页留在窗口里成为反方向的页，只有前进方向要渲染新页。
// 截图只含 WebView（背景 + 正文），章节名、页码由使用方按 page / chapter 自己画。
// WebView 要和主 WebView 同尺寸地挂在视图层级里，否则排版不一致或截不出内容。
final class PageRenderer {
    // 渲染一页约 100ms，和每秒翻十页的速度相当；前后各备三页，应付连续快速翻页
    private static let depth = 3

    let readers: [PageDirection: Reader]
    // 窗口围绕主 Reader 的新位置重建后回调中心页
    var onCurrent: ((RenderedPage) -> Void)?
    private var window: [RenderedPage] = []
    private var center = 0
    private var rendering: Set<PageDirection> = []
    private let main: Reader
    private var ready: Set<PageDirection> = []
    // 窗口每次作废加一，丢弃作废前开始的截图
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
            // 首次上报说明外壳页和 reader.js 已就绪
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

    // 版面变了（样式、尺寸）：丢掉所有截图，等主 Reader 重排后的上报重建
    func invalidate() {
        generation += 1
        window = []
        center = 0
    }

    // 主 Reader 每次落位后调用。落在窗口里说明它在跟随卷页层，窗口不变；
    // 否则（打开、跳转、重排）以新位置为中心重建
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

    // page 在 direction 一侧紧挨着的页；还没渲染好或到书头书尾时为 nil
    func neighbor(of page: RenderedPage, _ direction: PageDirection) -> RenderedPage? {
        guard let i = index(of: page.position) else { return nil }
        let j = i + direction.step
        return window.indices.contains(j) ? window[j] : nil
    }

    // 卷页层翻到了 page：以它为中心，两侧各留 depth 页，再往前续写
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

    // 同一个 WebView 只能串行渲染，每侧同时只续写一页
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
            // 窗口作废过，或这一侧最远那页已被 move(to:) 丢掉，结果接不上，从新的最远那页重来
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
            // 有效的 nil 是到了书头书尾，停下
            if !valid || page != nil { fill(direction) }
        }
    }
}
