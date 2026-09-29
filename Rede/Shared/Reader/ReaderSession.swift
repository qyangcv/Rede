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
    private(set) var book: Book?
    private(set) var page: PageInfo?
    private(set) var chapter: TOCItem?
    private var store: ProgressStore?
    
    init() {
        #if os(macOS)
        let name = NSApplication.willTerminateNotification
        #else
        let name = UIApplication.didEnterBackgroundNotification
        #endif
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store?.flush() }
        }
    }
    
    func open(_ book: Book, context: ModelContext) throws {
        if self.book?.id == book.id, reader != nil { return }
        store?.flush()

        let epub = try parseEpub(at: book.url)
        book.lastRead = .now
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let store = ProgressStore(book: book, context: context)
        let reader = Reader(book: epub, start: book.position)
        reader.onProgress = { [weak self] position, page, chapter in
            MainActor.assumeIsolated {
                store.record(position)
                self?.page = page
                self?.chapter = chapter
            }
        }

        self.store = store
        self.reader = reader
        self.book = book
        self.page = nil
        self.chapter = nil
    }

    func close() {
        store?.flush()
        store = nil
        reader = nil
        book = nil
        page = nil
        chapter = nil
    }
}

