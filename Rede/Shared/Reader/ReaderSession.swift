import Foundation
import Observation
import SwiftData
#if os(iOS)
import UIKit
#endif

@Observable
final class ReaderSession {
    private(set) var reader: Reader?
    private(set) var turner: (any PageTurner)?
    private(set) var book: Book?
    private(set) var page: PageInfo?
    private(set) var chapter: TOCItem?
    let history = JumpHistory()
    private(set) var jumpCount = 0
    private var store: ProgressStore?
    private var shownPosition: ReadingPosition?
    private var annotationStore: AnnotationStore?
    private var clock: ReadingClock?
    private var foreground = false
    private(set) var annotations: [Annotation] = []
    private var observers: [NSObjectProtocol] = []

    var bookmarks: [Annotation] { annotations.filter { $0.kind == .bookmark } }
    var highlights: [Annotation] { annotations.filter { $0.kind == .highlight } }
    var isBookmarked: Bool { !(page?.bookmarks.isEmpty ?? true) }
    var canBookmark: Bool { page?.start != nil }

    init() {
        let center = NotificationCenter.default
        #if os(iOS)
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        })
        #endif
        observers.append(center.addObserver(forName: SyncMonitor.didImport, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followRemoteProgress()
                self?.pushAnnotations()
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func open(_ book: Book, context: ModelContext) throws {
        if self.book?.id == book.id, reader != nil { return }
        flush()

        let epub = try book.epub()
        book.lastRead = .now
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let store = ProgressStore(book: book, context: context)
        let annotationStore = AnnotationStore(bookID: book.id, context: context)
        let clock = ReadingClock(bookID: book.id, context: context)
        let reader = Reader(book: epub, start: book.position)
        let turner = Settings.shared.pageTransition.makeTurner(reader: reader)
        reader.onProgress = { [weak self, weak reader] position, page, chapter in
            MainActor.assumeIsolated {
                if reader?.navigated == true {
                    store.record(position)
                    clock.record(position)
                }
                self?.turner?.pages?.prepare(position, page: page, chapter: chapter)
                self?.page = page
                self?.chapter = chapter
            }
        }
        reader.onLink = { [weak self] chapter, anchor in
            self?.jump(chapter: chapter, anchor: anchor)
        }

        self.store = store
        self.annotationStore = annotationStore
        self.clock = clock
        self.reader = reader
        self.turner = turner
        self.book = book
        self.page = nil
        self.chapter = nil
        self.shownPosition = book.position
        history.clear()
        pushAnnotations()
        clock.setForeground(foreground)
    }

    func flush() {
        store?.flush()
        clock?.stop()
    }

    func close() {
        flush()
        clock = nil
        foreground = false
        store = nil
        annotationStore = nil
        annotations = []
        reader = nil
        turner = nil
        book = nil
        page = nil
        chapter = nil
        shownPosition = nil
        history.clear()
    }

    func setTransition(_ transition: PageTransition) {
        guard let reader else { return }
        turner?.detach()
        let turner = transition.makeTurner(reader: reader)
        if let position = reader.position, let page {
            turner.pages?.prepare(position, page: page, chapter: chapter)
        }
        self.turner = turner
    }

    func setForeground(_ foreground: Bool) {
        self.foreground = foreground
        clock?.setForeground(foreground)
    }

    private func followRemoteProgress() {
        guard let reader, !reader.navigated, let book, book.modelContext != nil,
              let position = book.position, position != shownPosition else { return }
        shownPosition = position
        reader.restore(position)
    }

    func toggleBookmark() {
        guard let annotationStore, let page, let reader, let position = reader.position else { return }
        if page.bookmarks.isEmpty {
            guard let start = page.start else { return }
            annotationStore.addBookmark(chapter: position.chapter, offset: start, text: page.excerpt,
                                        tocID: reader.tocItem(at: start)?.id)
        } else {
            annotationStore.delete(ids: page.bookmarks)
        }
        pushAnnotations()
    }

    func perform(_ action: AnnotationAction, editNote: @escaping (String, CGRect) -> Void) {
        switch action {
        case .highlightSelection:
            highlightSelection()
        case .noteSelection:
            highlightSelection(then: editNote)
        case .editNote(let hit):
            editNote(hit.id, hit.rect.cgRect)
        case .delete(let id):
            deleteAnnotation(id: id)
        }
    }

    private func highlightSelection(then created: ((String, CGRect) -> Void)? = nil) {
        guard let reader, let annotationStore else { return }
        Task {
            guard let selection = await reader.takeSelection(), self.reader === reader else { return }
            let tocID = reader.tocItem(chapter: selection.chapter, offset: selection.start, anchors: selection.anchors)?.id
            let annotation = annotationStore.addHighlight(selection, tocID: tocID)
            pushAnnotations()
            created?(annotation.id, selection.rect.cgRect)
        }
    }

    func annotation(id: String) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func setNote(_ note: String, of annotation: Annotation) {
        annotationStore?.setNote(note.trimmingCharacters(in: .whitespacesAndNewlines), of: annotation)
        pushAnnotations()
    }

    func deleteAnnotation(id: String) {
        annotationStore?.delete(ids: [id])
        pushAnnotations()
    }

    func go(to annotation: Annotation) {
        jump(to: annotation)
    }

    func jump(to entry: EpubTocEntry) {
        guard let reader else { return }
        recordJump()
        reader.go(to: entry)
    }

    func jump(to annotation: Annotation) {
        guard let reader else { return }
        if reader.position?.chapter != annotation.chapter || reader.position?.offset != annotation.start {
            recordJump()
        }
        reader.go(to: ReadingPosition(chapter: annotation.chapter, offset: annotation.start, total: 0, ratio: 0))
    }

    func jump(chapter: Int, anchor: String?) {
        guard let reader else { return }
        recordJump()
        reader.jump(chapter: chapter, anchor: anchor)
    }

    func jump(toSearchHit chapter: Int, start: Int, end: Int) {
        guard let reader else { return }
        if reader.position?.chapter != chapter || reader.position?.offset != start {
            recordJump()
        }
        reader.showSearchHit(chapter: chapter, start: start, end: end)
    }

    func goBack() {
        guard let reader, let target = history.goBack(from: currentJumpEntry()) else { return }
        reader.go(to: target.position)
    }

    func goForward() {
        guard let reader, let target = history.goForward(from: currentJumpEntry()) else { return }
        reader.go(to: target.position)
    }

    func goBack(to id: JumpEntry.ID) {
        guard let reader, let target = history.goBack(to: id, from: currentJumpEntry()) else { return }
        reader.go(to: target.position)
    }

    func goForward(to id: JumpEntry.ID) {
        guard let reader, let target = history.goForward(to: id, from: currentJumpEntry()) else { return }
        reader.go(to: target.position)
    }

    private func currentJumpEntry() -> JumpEntry? {
        guard let position = reader?.position else { return nil }
        return JumpEntry(
            position: position,
            chapterTitle: chapter?.entry.title,
            page: page?.page,
            pageCount: page?.pageCount
        )
    }

    private func recordJump() {
        guard let entry = currentJumpEntry() else { return }
        history.record(entry)
        jumpCount += 1
    }

    func progress(of annotation: Annotation) -> Double? {
        book?.progress(chapter: annotation.chapter, offset: annotation.start)
    }

    private func pushAnnotations() {
        guard let reader, let annotationStore else { return }
        let all = annotationStore.annotations().filter { $0.kind != nil }
        annotations = all
        let marks = all.compactMap { AnnotationMark($0) }
        guard marks != reader.annotations else { return }
        reader.setAnnotations(marks)
        turner?.pages?.setAnnotations(marks)
    }
}

