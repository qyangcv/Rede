import AppKit
import SwiftUI

struct ChapterTick: Equatable {
    let chapter: Int
    let progress: Double
    let title: String?
}

struct BookmarkTick: Identifiable, Equatable {
    let id: String
    let chapter: Int
    let offset: Int
    let progress: Double
    let text: String
    let title: String?
    let section: String?
}

struct BookProgressIndex: Equatable {
    struct TitleEntry: Equatable {
        let title: String
        let section: String?
    }

    static let empty = BookProgressIndex(chapterLengths: [], spinePaths: [], toc: [])

    let chapterLengths: [Int]
    let prefixSums: [Int]
    let total: Int
    let chapterTitles: [String?]
    let chapterSectionTitles: [String?]
    let tocTitlesByID: [String: TitleEntry]
    let ticksByDepth: [[ChapterTick]]

    var isEmpty: Bool { total == 0 }

    init(chapterLengths: [Int], spinePaths: [String], toc: [TOCItem]) {
        self.chapterLengths = chapterLengths
        var sums: [Int] = []
        sums.reserveCapacity(chapterLengths.count + 1)
        var running = 0
        sums.append(0)
        for length in chapterLengths {
            running += max(length, 0)
            sums.append(running)
        }
        self.prefixSums = sums
        self.total = running

        var spineIndex: [String: Int] = [:]
        spineIndex.reserveCapacity(spinePaths.count)
        for (i, path) in spinePaths.enumerated() where spineIndex[path] == nil {
            spineIndex[path] = i
        }

        var titles = Array<String?>(repeating: nil, count: spinePaths.count)
        var sectionTitles = Array<String?>(repeating: nil, count: spinePaths.count)
        var titleDepths = Array(repeating: -1, count: spinePaths.count)
        var byID: [String: TitleEntry] = [:]
        for item in toc {
            let nonEmpty = item.path.map(\.title).filter { !$0.isEmpty }
            if let leaf = nonEmpty.last {
                let section = nonEmpty.count > 1 ? nonEmpty.dropLast().joined(separator: " › ") : nil
                byID[item.id] = TitleEntry(title: leaf, section: section)
                if let spine = spineIndex[item.entry.path], item.depth > titleDepths[spine] {
                    titles[spine] = leaf
                    sectionTitles[spine] = section
                    titleDepths[spine] = item.depth
                }
            }
        }
        var inheritedTitle: String?
        var inheritedSection: String?
        for i in titles.indices {
            if let title = titles[i] {
                inheritedTitle = title
                inheritedSection = sectionTitles[i]
            } else {
                titles[i] = inheritedTitle
                sectionTitles[i] = inheritedSection
            }
        }
        self.chapterTitles = titles
        self.chapterSectionTitles = sectionTitles
        self.tocTitlesByID = byID

        if running > 0, !toc.isEmpty {
            let maxDepth = toc.map(\.depth).max() ?? 0
            var tiers: [[ChapterTick]] = []
            tiers.reserveCapacity(maxDepth + 1)
            for depth in 0...maxDepth {
                var seenSpines: Set<Int> = []
                var rawTicks: [ChapterTick] = []
                for item in toc where item.depth <= depth {
                    guard let spine = spineIndex[item.entry.path],
                          spine < chapterLengths.count,
                          seenSpines.insert(spine).inserted else { continue }
                    let p = Double(sums[spine]) / Double(running)
                    guard p > 0.002 && p < 0.998 else { continue }
                    let title = item.path.last(where: { !$0.title.isEmpty })?.title
                    rawTicks.append(ChapterTick(chapter: spine, progress: p, title: title))
                }
                rawTicks.sort { $0.progress < $1.progress }
                var deduped: [ChapterTick] = []
                deduped.reserveCapacity(rawTicks.count)
                for tick in rawTicks {
                    if let last = deduped.last, abs(tick.progress - last.progress) < 0.0001 {
                        continue
                    }
                    deduped.append(tick)
                }
                tiers.append(deduped)
            }
            self.ticksByDepth = tiers
        } else {
            self.ticksByDepth = []
        }
    }

    func progress(for position: ReadingPosition, page: PageInfo?) -> Double {
        let chapter = position.chapter
        guard total > 0, chapter >= 0, chapter < chapterLengths.count else { return 0 }
        if chapter == chapterLengths.count - 1, let page, page.pageCount > 0, page.page + 1 >= page.pageCount {
            return 1
        }
        let chapterLength = max(chapterLengths[chapter], 0)
        let chapterFraction: Double
        if position.offset >= 0, position.total > 0 {
            chapterFraction = min(max(Double(position.offset) / Double(position.total), 0), 1)
        } else if position.offset >= 0, chapterLength > 0 {
            chapterFraction = min(max(Double(position.offset) / Double(chapterLength), 0), 1)
        } else {
            chapterFraction = min(max(position.ratio, 0), 1)
        }
        let read = Double(prefixSums[chapter]) + Double(chapterLength) * chapterFraction
        return min(max(read / Double(total), 0), 1)
    }

    func progress(chapter: Int, offset: Int) -> Double? {
        guard total > 0, chapter >= 0, chapter < chapterLengths.count else { return nil }
        let clampedOffset = min(max(offset, 0), max(chapterLengths[chapter], 0))
        let read = prefixSums[chapter] + clampedOffset
        return min(max(Double(read) / Double(total), 0), 1)
    }

    func position(at progress: Double) -> ReadingPosition? {
        guard total > 0, !chapterLengths.isEmpty else { return nil }
        let clamped = min(max(progress, 0), 1)
        if clamped <= 0 {
            let first = chapterLengths.firstIndex { $0 > 0 } ?? 0
            return ReadingPosition(chapter: first, offset: 0, total: max(chapterLengths[first], 0), ratio: 0)
        }
        if clamped >= 1 {
            let last = chapterLengths.lastIndex { $0 > 0 } ?? (chapterLengths.count - 1)
            let length = max(chapterLengths[last], 0)
            return ReadingPosition(chapter: last, offset: length, total: length, ratio: 1)
        }
        let target = min(Int((clamped * Double(total)).rounded(.down)), total - 1)
        var lo = 0
        var hi = chapterLengths.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if prefixSums[mid] <= target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let chapter = max(lo - 1, 0)
        let length = max(chapterLengths[chapter], 0)
        let offset = min(max(target - prefixSums[chapter], 0), length)
        let ratio = length > 0 ? Double(offset) / Double(length) : 0
        return ReadingPosition(chapter: chapter, offset: offset, total: length, ratio: ratio)
    }

    func chapterStart(for chapter: Int) -> ReadingPosition? {
        guard chapterLengths.indices.contains(chapter) else { return nil }
        return ReadingPosition(chapter: chapter, offset: 0, total: max(chapterLengths[chapter], 0), ratio: 0)
    }

    func chapterTitle(for chapter: Int) -> String? {
        guard chapterTitles.indices.contains(chapter) else { return nil }
        return chapterTitles[chapter]
    }

    func sectionTitle(for chapter: Int) -> String? {
        guard chapterSectionTitles.indices.contains(chapter) else { return nil }
        return chapterSectionTitles[chapter]
    }

    func visibleTicks(for trackWidth: CGFloat) -> [ChapterTick] {
        guard total > 0, trackWidth > 0, !ticksByDepth.isEmpty else { return [] }
        let maxTicks = max(Int(trackWidth / 12), 1)
        let minGapFraction = Double(5 / trackWidth)
        for depth in stride(from: ticksByDepth.count - 1, through: 0, by: -1) {
            let candidates = ticksByDepth[depth]
            guard candidates.count <= maxTicks else { continue }
            var result: [ChapterTick] = []
            result.reserveCapacity(candidates.count)
            for tick in candidates {
                if let last = result.last, tick.progress - last.progress < minGapFraction {
                    continue
                }
                result.append(tick)
            }
            return result
        }
        return []
    }

    func bookmarkTicks(for bookmarks: [Annotation]) -> [BookmarkTick] {
        guard total > 0, !bookmarks.isEmpty else { return [] }
        let items = bookmarks.compactMap { bookmark -> BookmarkTick? in
            guard let p = progress(chapter: bookmark.chapter, offset: bookmark.start) else { return nil }
            let resolved = bookmark.tocID.flatMap { tocTitlesByID[$0] }
            let title = resolved?.title ?? chapterTitle(for: bookmark.chapter)
            let section = resolved?.section ?? sectionTitle(for: bookmark.chapter)
            return BookmarkTick(id: bookmark.id, chapter: bookmark.chapter, offset: bookmark.start,
                                progress: p, text: bookmark.text, title: title, section: section)
        }
        .sorted { $0.progress < $1.progress }
        var result: [BookmarkTick] = []
        result.reserveCapacity(items.count)
        for item in items {
            if let last = result.last, item.progress - last.progress < 0.006 { continue }
            result.append(item)
        }
        return result
    }
}

enum BookProgressFormat {
    static func text(for progress: Double) -> String {
        let clamped = min(max(progress, 0), 1)
        if clamped <= 0 { return "0%" }
        if clamped >= 1 { return "100%" }
        return clamped.formatted(.percent.precision(.fractionLength(1)).rounded(rule: .down))
    }
}

struct ReaderProgressBar: View {
    let page: PageInfo
    let position: ReadingPosition?
    let progressRevision: Int
    let chapterLengths: [Int]
    let spine: [EpubManifestItem]
    let toc: [TOCItem]
    let bookmarks: [Annotation]
    let loadEpubData: () -> Data?
    let activeChapterTitle: (Int) -> String?
    let onJump: (ReadingPosition) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var settings = Settings.shared

    @State private var index: BookProgressIndex = .empty
    @State private var bookmarkMarks: [BookmarkTick] = []
    @State private var previewStore: ChapterPreviewStore?
    @State private var hovering = false
    @State private var hoverProgress: Double?
    @State private var snappedTick: ChapterTick?
    @State private var snappedBookmark: BookmarkTick?
    @State private var dragProgress: Double?
    @State private var didDrag = false
    @State private var pendingProgress: Double?
    @State private var dragCancelled = false
    @State private var cardHeight: CGFloat = 104
    @State private var trackSlotWidth: CGFloat = 0
    @State private var escMonitor: Any?

    private let thumbDiameter: CGFloat = 11
    private let activeThumbDiameter: CGFloat = 13
    private let sideSlotWidth: CGFloat = 52
    private let trackSpacing: CGFloat = 12
    private let minTrackWidth: CGFloat = 180
    private let cardWidth: CGFloat = 264
    private let previewLineLimit = 6
    private let snapThreshold: CGFloat = 5
    private let bookmarkSnapThreshold: CGFloat = 6

    private var liveProgress: Double {
        guard let position, !index.isEmpty else { return 0 }
        return index.progress(for: position, page: page)
    }

    private var displayProgress: Double {
        dragProgress ?? pendingProgress ?? liveProgress
    }

    private var canScrub: Bool {
        !index.isEmpty && trackSlotWidth >= minTrackWidth
    }

    private var showScrubber: Bool {
        canScrub && (hovering || dragProgress != nil)
    }

    private var bookmarkIDs: [String] {
        bookmarks.map(\.id)
    }

    private var visibleBookmarks: [BookmarkTick] {
        settings.showProgressBarBookmarks ? bookmarkMarks : []
    }

    private var activePreviewProgress: Double? {
        dragProgress ?? snappedBookmark?.progress ?? snappedTick?.progress ?? hoverProgress
    }

    private var activePreviewTarget: ReadingPosition? {
        if let snappedBookmark {
            let length = index.chapterLengths.indices.contains(snappedBookmark.chapter)
                ? max(index.chapterLengths[snappedBookmark.chapter], 0) : 0
            let ratio = length > 0 ? min(max(Double(snappedBookmark.offset) / Double(length), 0), 1) : 0
            return ReadingPosition(chapter: snappedBookmark.chapter, offset: snappedBookmark.offset,
                                   total: length, ratio: ratio)
        }
        if let snappedTick {
            return index.chapterStart(for: snappedTick.chapter)
        }
        guard let progress = activePreviewProgress,
              let resolved = index.position(at: progress) else { return nil }
        return index.chapterStart(for: resolved.chapter)
    }

    private var activePreviewKey: ChapterPreviewKey? {
        if let snappedBookmark {
            return ChapterPreviewKey(chapter: snappedBookmark.chapter, offset: snappedBookmark.offset)
        }
        guard let chapter = activePreviewTarget?.chapter else { return nil }
        return ChapterPreviewKey(chapter: chapter, offset: nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: sideSlotWidth + trackSpacing, height: 1)
                .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: trackSpacing) {
                ZStack(alignment: .bottom) {
                    if showScrubber {
                        scrubberTrack
                            .padding(.bottom, ReaderLayout.pageNumberBottom - 4)
                            .transition(.opacity)
                    } else {
                        restingLabel
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(ReaderLayout.marginBottom), alignment: .bottom)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackSlotWidth = $0 }

                ZStack(alignment: .leading) {
                    Text("100.0%").hidden()
                    if showScrubber {
                        Text(BookProgressFormat.text(for: displayProgress))
                            .transition(.opacity)
                    }
                }
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: sideSlotWidth, alignment: .leading)
                .frame(height: 24)
                .padding(.bottom, ReaderLayout.pageNumberBottom - 4)
                .fixedSize()
            }
            .frame(height: CGFloat(ReaderLayout.marginBottom), alignment: .bottom)
            .contentShape(Rectangle())
            .onHover { isOver in
                hovering = isOver
                if !isOver && dragProgress == nil {
                    hoverProgress = nil
                    snappedTick = nil
                    snappedBookmark = nil
                }
            }
            .allowsHitTesting(canScrub)
        }
        .frame(maxWidth: 648)
        .padding(.horizontal, CGFloat(ReaderLayout.gutter))
        .animation(.easeInOut(duration: 0.16), value: showScrubber)
        .onChange(of: canScrub) { _, allowed in
            if !allowed {
                hovering = false
                hoverProgress = nil
                snappedTick = nil
                snappedBookmark = nil
            }
        }
        .onChange(of: settings.showProgressBarBookmarks) { _, shown in
            if !shown { snappedBookmark = nil }
        }
        .onChange(of: chapterLengths, initial: true) { _, lengths in
            let rebuilt = BookProgressIndex(chapterLengths: lengths, spinePaths: spine.map(\.path), toc: toc)
            index = rebuilt
            bookmarkMarks = rebuilt.bookmarkTicks(for: bookmarks)
        }
        .onChange(of: bookmarkIDs) {
            bookmarkMarks = index.bookmarkTicks(for: bookmarks)
            if let current = snappedBookmark, !bookmarkMarks.contains(where: { $0.id == current.id }) {
                snappedBookmark = nil
            }
        }
        .onChange(of: progressRevision) {
            pendingProgress = nil
        }
        .onChange(of: activePreviewKey) { _, key in
            guard let key else { return }
            if previewStore == nil {
                previewStore = ChapterPreviewStore(epubData: loadEpubData(), spinePaths: spine.map(\.path),
                                                   maxLines: previewLineLimit)
            }
            if let offset = key.offset {
                previewStore?.load(chapter: key.chapter, offset: offset, fallbackText: snappedBookmark?.text ?? "")
            } else {
                let title = index.chapterTitle(for: key.chapter)
                previewStore?.load(chapter: key.chapter, title: title)
            }
        }
        .onDisappear {
            removeEscMonitor()
            previewStore?.cancelAll()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("阅读进度")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !index.isEmpty, let current = position?.chapter else { return }
            let step = direction == .increment ? 1 : -1
            var next = current + step
            while index.chapterLengths.indices.contains(next), index.chapterLengths[next] <= 0 {
                next += step
            }
            guard index.chapterLengths.indices.contains(next) else { return }
            commitChapterStart(next)
        }
    }

    private var accessibilityValue: String {
        let chapterPage = "第 \(page.page + 1) 页，共 \(page.pageCount) 页"
        guard !index.isEmpty else { return chapterPage }
        return "\(chapterPage)，全书 \(BookProgressFormat.text(for: displayProgress))"
    }

    private var restingLabel: some View {
        Text("\(page.page + 1) / \(page.pageCount)")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.bottom, ReaderLayout.pageNumberBottom)
    }

    private var scrubberTrack: some View {
        GeometryReader { geo in
            let radius = activeThumbDiameter / 2
            let trackWidth = max(geo.size.width - activeThumbDiameter, 1)
            let clamped = min(max(displayProgress, 0), 1)
            let thumbX = radius + trackWidth * clamped
            let currentThumb = dragProgress != nil ? activeThumbDiameter : thumbDiameter
            let ticks = index.visibleTicks(for: trackWidth)
            let bookmarksOnTrack = visibleBookmarks
            let effectiveHover = dragProgress == nil ? (snappedBookmark?.progress ?? snappedTick?.progress ?? hoverProgress) : nil
            let showHoverMarker = effectiveHover != nil && snappedBookmark == nil

            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let midY = size.height / 2
                    let startX = radius
                    let endX = radius + trackWidth
                    let gap: CGFloat = 2
                    let boundaries = [startX] + ticks.map { radius + trackWidth * $0.progress } + [endX]
                    let fillEndX = radius + trackWidth * clamped
                    let hoverX = effectiveHover.map { radius + trackWidth * $0 }

                    for i in 0..<(boundaries.count - 1) {
                        let rawLeft = boundaries[i]
                        let rawRight = boundaries[i + 1]
                        let segLeft = i == 0 ? rawLeft : rawLeft + gap / 2
                        let segRight = i == boundaries.count - 2 ? rawRight : rawRight - gap / 2
                        let segWidth = segRight - segLeft
                        guard segWidth > 0.5 else { continue }

                        let isHoveredSegment = !ticks.isEmpty && hoverX.map { $0 >= rawLeft && $0 <= rawRight } == true
                        let height: CGFloat = isHoveredSegment ? 5 : 3.5
                        let rect = CGRect(x: segLeft, y: midY - height / 2, width: segWidth, height: height)
                        let path = Path(roundedRect: rect, cornerRadius: height / 2)

                        context.fill(path, with: .color(.primary.opacity(isHoveredSegment ? 0.22 : 0.14)))

                        if let hoverX, hoverX > segLeft {
                            let hoverWidth = min(hoverX, segRight) - segLeft
                            if hoverWidth > 0 {
                                var clipped = context
                                clipped.clip(to: path)
                                clipped.fill(
                                    Path(CGRect(x: segLeft, y: midY - height / 2, width: hoverWidth, height: height)),
                                    with: .color(.primary.opacity(0.14))
                                )
                            }
                        }

                        if fillEndX > segLeft {
                            let activeWidth = min(fillEndX, segRight) - segLeft
                            if activeWidth > 0 {
                                var clipped = context
                                clipped.clip(to: path)
                                clipped.fill(
                                    Path(CGRect(x: segLeft, y: midY - height / 2, width: activeWidth, height: height)),
                                    with: .color(Color.accentColor.opacity(0.85))
                                )
                            }
                        }
                    }

                    if showHoverMarker, let hoverX {
                        let marker = Path(
                            roundedRect: CGRect(x: hoverX - 1, y: midY - 4.5, width: 2, height: 9),
                            cornerRadius: 1
                        )
                        context.fill(marker, with: .color(.primary.opacity(0.45)))
                    }
                }

                ForEach(bookmarksOnTrack) { mark in
                    let isSnapped = snappedBookmark?.id == mark.id
                    Capsule()
                        .fill(Color.red.opacity(isSnapped ? 1 : 0.8))
                        .frame(width: isSnapped ? 3 : 2.5, height: isSnapped ? 10 : 7)
                        .position(x: radius + trackWidth * mark.progress, y: geo.size.height / 2)
                        .animation(.easeOut(duration: 0.12), value: isSnapped)
                }

                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .frame(width: currentThumb, height: currentThumb)
                    .position(x: thumbX, y: geo.size.height / 2)
                    .animation(.easeOut(duration: 0.12), value: dragProgress != nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard dragProgress == nil else { return }
                    let raw = fraction(for: location.x, radius: radius, trackWidth: trackWidth)
                    if let bookmark = nearestBookmark(to: location.x, bookmarks: bookmarksOnTrack,
                                                      radius: radius, trackWidth: trackWidth) {
                        snappedBookmark = bookmark
                        snappedTick = nil
                        hoverProgress = bookmark.progress
                    } else if let tick = nearestTick(to: location.x, ticks: ticks, radius: radius, trackWidth: trackWidth) {
                        snappedBookmark = nil
                        snappedTick = tick
                        hoverProgress = tick.progress
                    } else {
                        snappedBookmark = nil
                        snappedTick = nil
                        hoverProgress = raw
                    }
                case .ended:
                    if dragProgress == nil {
                        hoverProgress = nil
                        snappedTick = nil
                        snappedBookmark = nil
                    }
                }
            }
            .overlay {
                if let previewProgress = activePreviewProgress, let target = activePreviewTarget {
                    let anchorX = radius + trackWidth * previewProgress
                    let sideMargin = CGFloat(ReaderLayout.gutter) + sideSlotWidth + trackSpacing
                    let minX = -sideMargin + 12 + cardWidth / 2
                    let maxX = geo.size.width + sideMargin - 12 - cardWidth / 2
                    let cardX = min(max(anchorX, minX), maxX)

                    previewCard(for: target, progress: previewProgress, bookmark: snappedBookmark)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        .position(x: cardX, y: -(cardHeight / 2) - 8)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragCancelled { return }
                        if !didDrag && abs(value.translation.width) >= 4 {
                            didDrag = true
                            installEscMonitor()
                        }
                        if didDrag {
                            let raw = fraction(for: value.location.x, radius: radius, trackWidth: trackWidth)
                            if let bookmark = nearestBookmark(to: value.location.x, bookmarks: bookmarksOnTrack,
                                                              radius: radius, trackWidth: trackWidth) {
                                snappedBookmark = bookmark
                                snappedTick = nil
                                dragProgress = bookmark.progress
                            } else if let tick = nearestTick(to: value.location.x, ticks: ticks, radius: radius, trackWidth: trackWidth) {
                                snappedBookmark = nil
                                snappedTick = tick
                                dragProgress = tick.progress
                            } else {
                                snappedBookmark = nil
                                snappedTick = nil
                                dragProgress = raw
                            }
                        }
                    }
                    .onEnded { value in
                        removeEscMonitor()
                        if dragCancelled {
                            dragCancelled = false
                            didDrag = false
                            dragProgress = nil
                            snappedTick = nil
                            snappedBookmark = nil
                            return
                        }
                        if didDrag {
                            let finalBookmark = snappedBookmark
                            let finalTick = snappedTick
                            let finalProgress = fraction(for: value.location.x, radius: radius, trackWidth: trackWidth)
                            didDrag = false
                            dragProgress = nil
                            snappedTick = nil
                            snappedBookmark = nil
                            if let finalBookmark {
                                commitBookmark(finalBookmark)
                            } else if let finalTick {
                                commitChapterStart(finalTick.chapter)
                            } else {
                                commitChapter(at: finalProgress)
                            }
                        } else if let snappedBookmark {
                            commitBookmark(snappedBookmark)
                        } else if let snappedTick {
                            commitChapterStart(snappedTick.chapter)
                        } else {
                            let clickProgress = hoverProgress ?? fraction(for: value.location.x, radius: radius, trackWidth: trackWidth)
                            commitChapter(at: clickProgress)
                        }
                    }
            )
        }
        .frame(height: 24)
    }

    private func previewCard(for target: ReadingPosition, progress: Double, bookmark: BookmarkTick?) -> some View {
        let title = bookmark?.title ?? previewTitle(for: target)
        let section = bookmark != nil ? bookmark?.section : index.sectionTitle(for: target.chapter)
        let key = bookmark.map { ChapterPreviewKey(chapter: $0.chapter, offset: $0.offset) }
            ?? ChapterPreviewKey(chapter: target.chapter, offset: nil)
        let content = previewStore?.cached(key: key)
        let headerProgress = bookmark?.progress ?? index.progress(chapter: target.chapter, offset: 0) ?? progress
        let paperColor = settings.readerStyle.background.swatch(for: colorScheme)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let section, !section.isEmpty {
                        Text(section)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 4) {
                        if bookmark != nil {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else if bookmark != nil {
                            Text("书签")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                Spacer(minLength: 4)
                Text(BookProgressFormat.text(for: headerProgress))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)

            Group {
                switch content {
                case .text(let paragraphs):
                    Text(paragraphs.joined(separator: "\n"))
                        .font(.system(size: 12))
                        .lineSpacing(3.5)
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(previewLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.72),
                                    .init(color: .black.opacity(0.28), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                case .illustration:
                    HStack(spacing: 5) {
                        Image(systemName: "photo")
                        Text("插图页")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .empty:
                    Color.clear
                        .frame(height: 18)
                case nil:
                    Text(Array(repeating: " ", count: max(previewLineLimit, 1)).joined(separator: "\n"))
                        .font(.system(size: 12))
                        .lineSpacing(3.5)
                        .hidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: cardWidth)
        .background(paperColor, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.14), radius: 12, y: 4)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }

    private func previewTitle(for target: ReadingPosition) -> String? {
        if let snappedTick, let tickTitle = snappedTick.title, !tickTitle.isEmpty {
            return tickTitle
        }
        if target.chapter == position?.chapter, let active = activeChapterTitle(0), !active.isEmpty {
            return active
        }
        return index.chapterTitle(for: target.chapter)
    }

    private func nearestBookmark(to x: CGFloat, bookmarks: [BookmarkTick],
                                 radius: CGFloat, trackWidth: CGFloat) -> BookmarkTick? {
        var best: BookmarkTick?
        var bestDistance = bookmarkSnapThreshold
        for mark in bookmarks {
            let markX = radius + trackWidth * mark.progress
            let distance = abs(x - markX)
            if distance <= bestDistance {
                bestDistance = distance
                best = mark
            }
        }
        return best
    }

    private func nearestTick(to x: CGFloat, ticks: [ChapterTick],
                             radius: CGFloat, trackWidth: CGFloat) -> ChapterTick? {
        var best: ChapterTick?
        var bestDistance = snapThreshold
        for tick in ticks {
            let tickX = radius + trackWidth * tick.progress
            let distance = abs(x - tickX)
            if distance <= bestDistance {
                bestDistance = distance
                best = tick
            }
        }
        return best
    }

    private func fraction(for x: CGFloat, radius: CGFloat, trackWidth: CGFloat) -> Double {
        min(max(Double((x - radius) / trackWidth), 0), 1)
    }

    private func commitBookmark(_ mark: BookmarkTick) {
        guard index.chapterLengths.indices.contains(mark.chapter) else { return }
        let length = max(index.chapterLengths[mark.chapter], 0)
        let ratio = length > 0 ? min(max(Double(mark.offset) / Double(length), 0), 1) : 0
        let target = ReadingPosition(chapter: mark.chapter, offset: mark.offset, total: length, ratio: ratio)
        if target.chapter == position?.chapter && target.offset == position?.offset {
            return
        }
        pendingProgress = mark.progress
        onJump(target)
    }

    private func commitChapter(at progress: Double) {
        guard let target = index.position(at: progress) else { return }
        commitChapterStart(target.chapter)
    }

    private func commitChapterStart(_ chapter: Int) {
        guard let target = index.chapterStart(for: chapter) else { return }
        if target.chapter == position?.chapter && target.offset == position?.offset {
            return
        }
        pendingProgress = index.progress(chapter: chapter, offset: 0)
        onJump(target)
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                dragCancelled = true
                didDrag = false
                dragProgress = nil
                snappedTick = nil
                snappedBookmark = nil
                removeEscMonitor()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}
