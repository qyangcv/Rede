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
    // 阅读器当前落在的已保存进度；翻页之前，其他设备同步来不同的进度就跟过去，见 followRemoteProgress()
    private var shownPosition: ReadingPosition?

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
            MainActor.assumeIsolated { self?.followRemoteProgress() }
        }
    }

    func open(_ book: Book, context: ModelContext) throws {
        if self.book?.id == book.id, reader != nil { return }
        store?.flush()

        let epub = try book.epub()
        book.lastRead = .now
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let store = ProgressStore(book: book, context: context)
        let reader = Reader(book: epub, start: book.position)
        let turner = Settings.shared.pageTransition.makeTurner(reader: reader)
        reader.onProgress = { [weak self, weak reader] position, page, chapter in
            MainActor.assumeIsolated {
                // 翻页之前的上报只是落位（打开、窗口缩放、跟随同步来的进度），不算阅读进度
                if reader?.navigated == true { store.record(position) }
                self?.turner?.pages?.prepare(position, page: page, chapter: chapter)
                self?.page = page
                self?.chapter = chapter
            }
        }

        self.store = store
        self.reader = reader
        self.turner = turner
        self.book = book
        self.page = nil
        self.chapter = nil
        self.shownPosition = book.position
    }

    func flush() {
        store?.flush()
    }

    func close() {
        store?.flush()
        store = nil
        reader = nil
        turner = nil
        book = nil
        page = nil
        chapter = nil
        shownPosition = nil
    }

    // 阅读中切换翻页方式：换掉翻页器，新的相邻页窗口围绕当前页建立
    func setTransition(_ transition: PageTransition) {
        guard let reader else { return }
        turner?.detach()
        let turner = transition.makeTurner(reader: reader)
        if let position = reader.position, let page {
            turner.pages?.prepare(position, page: page, chapter: chapter)
        }
        self.turner = turner
    }

    // 刚打开、还没翻页时，其他设备同步来了这本书更新的进度：直接跳过去
    private func followRemoteProgress() {
        guard let reader, !reader.navigated, let book, book.modelContext != nil,
              let position = book.position, position != shownPosition else { return }
        shownPosition = position
        reader.restore(position)
    }
}

