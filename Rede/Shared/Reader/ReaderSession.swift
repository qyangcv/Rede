import Foundation
import Observation
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class ReaderSession {
    static let windowID = "reader"

    private(set) var reader: Reader?
    private(set) var turner: (any PageTurner)?
    private(set) var book: Book?
    private(set) var page: PageInfo?
    private(set) var chapter: TOCItem?
    private var store: ProgressStore?
    private var shownPosition: ReadingPosition?
    private var annotationStore: AnnotationStore?
    private(set) var annotations: [Annotation] = []

    var bookmarks: [Annotation] { annotations.filter { $0.kind == .bookmark } }
    var highlights: [Annotation] { annotations.filter { $0.kind == .highlight } }
    var isBookmarked: Bool { !(page?.bookmarks.isEmpty ?? true) }
    var canBookmark: Bool { page?.start != nil }

    init() {
        #if os(macOS)
        let name = NSApplication.willTerminateNotification
        #else
        let name = UIApplication.didEnterBackgroundNotification
        #endif
        let center = NotificationCenter.default
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        center.addObserver(forName: SyncMonitor.didImport, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followRemoteProgress()
                self?.pushAnnotations()
            }
        }
    }

    func open(_ book: Book, context: ModelContext) throws {
        if self.book?.id == book.id, reader != nil { return }
        store?.flush()

        let epub = try book.epub()
        book.lastRead = .now
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let store = ProgressStore(book: book, context: context)
        let annotationStore = AnnotationStore(bookID: book.id, context: context)
        let reader = Reader(book: epub, start: book.position)
        let turner = Settings.shared.pageTransition.makeTurner(reader: reader)
        reader.onProgress = { [weak self, weak reader] position, page, chapter in
            MainActor.assumeIsolated {
                if reader?.navigated == true { store.record(position) }
                self?.turner?.pages?.prepare(position, page: page, chapter: chapter)
                self?.page = page
                self?.chapter = chapter
            }
        }

        self.store = store
        self.annotationStore = annotationStore
        self.reader = reader
        self.turner = turner
        self.book = book
        self.page = nil
        self.chapter = nil
        self.shownPosition = book.position
        pushAnnotations()
    }

    func flush() {
        store?.flush()
    }

    func close() {
        store?.flush()
        store = nil
        annotationStore = nil
        annotations = []
        reader = nil
        turner = nil
        book = nil
        page = nil
        chapter = nil
        shownPosition = nil
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

    private func followRemoteProgress() {
        guard let reader, !reader.navigated, let book, book.modelContext != nil,
              let position = book.position, position != shownPosition else { return }
        shownPosition = position
        reader.restore(position)
    }

    func toggleBookmark() {
        guard let annotationStore, let page, let position = reader?.position else { return }
        if page.bookmarks.isEmpty {
            guard let start = page.start else { return }
            annotationStore.addBookmark(chapter: position.chapter, offset: start, text: page.excerpt)
        } else {
            annotationStore.delete(ids: page.bookmarks)
        }
        pushAnnotations()
    }

    func highlightSelection(then created: ((Annotation, CGRect) -> Void)? = nil) {
        guard let reader, let annotationStore else { return }
        Task {
            guard let selection = await reader.takeSelection() else { return }
            let annotation = annotationStore.addHighlight(selection)
            pushAnnotations()
            created?(annotation, selection.rect.cgRect)
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
        reader?.go(to: ReadingPosition(chapter: annotation.chapter, offset: annotation.start, total: 0, ratio: 0))
    }

    func progress(of annotation: Annotation) -> Double? {
        book?.progress(chapter: annotation.chapter, offset: annotation.start)
    }

    private func pushAnnotations() {
        guard let reader, let annotationStore else { return }
        let all = annotationStore.annotations().filter { $0.kind != nil }
        annotations = all
        let marks = all.compactMap(AnnotationMark.init)
        guard marks != reader.annotations else { return }
        reader.setAnnotations(marks)
        turner?.pages?.setAnnotations(marks)
    }
}

