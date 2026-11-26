import AppKit
import SwiftUI

struct BookProgressIndex: Equatable {
    static let empty = BookProgressIndex(chapterLengths: [], spinePaths: [], toc: [])

    let chapterLengths: [Int]
    let prefixSums: [Int]
    let total: Int
    let chapterTitles: [String?]

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
        for item in toc {
            guard let spine = spineIndex[item.entry.path], titles[spine] == nil else { continue }
            if let title = item.path.last(where: { !$0.title.isEmpty })?.title {
                titles[spine] = title
            }
        }
        var inherited: String?
        for i in titles.indices {
            if let title = titles[i] {
                inherited = title
            } else {
                titles[i] = inherited
            }
        }
        self.chapterTitles = titles
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

    func chapterTitle(for chapter: Int) -> String? {
        guard chapterTitles.indices.contains(chapter) else { return nil }
        return chapterTitles[chapter]
    }

    func bookmarkPositions(for bookmarks: [Annotation]) -> [Double] {
        guard total > 0, !bookmarks.isEmpty else { return [] }
        let sorted = bookmarks.compactMap { progress(chapter: $0.chapter, offset: $0.start) }.sorted()
        var result: [Double] = []
        result.reserveCapacity(sorted.count)
        for value in sorted {
            if let last = result.last, value - last < 0.006 { continue }
            result.append(value)
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
    let activeChapterTitle: (Int) -> String?
    let onJump: (ReadingPosition) -> Void

    @State private var index: BookProgressIndex = .empty
    @State private var bookmarkMarks: [Double] = []
    @State private var hovering = false
    @State private var dragProgress: Double?
    @State private var pendingProgress: Double?
    @State private var dragCancelled = false
    @State private var pillWidth: CGFloat = 0
    @State private var trackSlotWidth: CGFloat = 0
    @State private var escMonitor: Any?

    private let thumbDiameter: CGFloat = 11
    private let activeThumbDiameter: CGFloat = 13
    private let sideSlotWidth: CGFloat = 52
    private let trackSpacing: CGFloat = 12
    private let minTrackWidth: CGFloat = 180

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
            .onHover { hovering = $0 }
            .allowsHitTesting(canScrub)
        }
        .frame(maxWidth: 648)
        .padding(.horizontal, CGFloat(ReaderLayout.gutter))
        .animation(.easeInOut(duration: 0.16), value: showScrubber)
        .onChange(of: canScrub) { _, allowed in
            if !allowed { hovering = false }
        }
        .onChange(of: chapterLengths, initial: true) { _, lengths in
            let rebuilt = BookProgressIndex(chapterLengths: lengths, spinePaths: spine.map(\.path), toc: toc)
            index = rebuilt
            bookmarkMarks = rebuilt.bookmarkPositions(for: bookmarks)
        }
        .onChange(of: bookmarkIDs) {
            bookmarkMarks = index.bookmarkPositions(for: bookmarks)
        }
        .onChange(of: progressRevision) {
            pendingProgress = nil
        }
        .onDisappear {
            removeEscMonitor()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("阅读进度")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !index.isEmpty else { return }
            let delta = direction == .increment ? 0.02 : -0.02
            let next = min(max(liveProgress + delta, 0), 1)
            commit(next)
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

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.14))
                    .frame(height: 3.5)
                    .padding(.horizontal, radius)

                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: max(trackWidth * clamped, 0), height: 3.5)
                    .padding(.leading, radius)

                ForEach(Array(bookmarkMarks.enumerated()), id: \.offset) { _, mark in
                    Capsule()
                        .fill(.secondary.opacity(0.55))
                        .frame(width: 2, height: 6)
                        .position(x: radius + trackWidth * mark, y: geo.size.height / 2)
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
            .overlay {
                if let dragValue = dragProgress {
                    let minX = min(pillWidth / 2, geo.size.width / 2)
                    let maxX = max(geo.size.width - pillWidth / 2, geo.size.width / 2)
                    let pillX = min(max(thumbX, minX), maxX)

                    previewPill(for: dragValue)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pillWidth = $0 }
                        .position(x: pillX, y: -18)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragCancelled { return }
                        if dragProgress == nil { installEscMonitor() }
                        dragProgress = fraction(for: value.location.x, radius: radius, trackWidth: trackWidth)
                    }
                    .onEnded { value in
                        removeEscMonitor()
                        if dragCancelled {
                            dragCancelled = false
                            dragProgress = nil
                            return
                        }
                        let finalProgress = fraction(for: value.location.x, radius: radius, trackWidth: trackWidth)
                        dragProgress = nil
                        commit(finalProgress)
                    }
            )
        }
        .frame(height: 24)
    }

    private func previewPill(for progress: Double) -> some View {
        let target = index.position(at: progress)
        let title = previewTitle(for: target)

        return VStack(spacing: 1) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220)
            }
            Text(BookProgressFormat.text(for: progress))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
    }

    private func previewTitle(for target: ReadingPosition?) -> String? {
        guard let target else { return nil }
        if target.chapter == position?.chapter, let active = activeChapterTitle(target.offset) {
            return active
        }
        return index.chapterTitle(for: target.chapter)
    }

    private func fraction(for x: CGFloat, radius: CGFloat, trackWidth: CGFloat) -> Double {
        min(max(Double((x - radius) / trackWidth), 0), 1)
    }

    private func commit(_ progress: Double) {
        guard let target = index.position(at: progress) else { return }
        if target.chapter == position?.chapter && target.offset == position?.offset {
            return
        }
        pendingProgress = progress
        onJump(target)
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                dragCancelled = true
                dragProgress = nil
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
