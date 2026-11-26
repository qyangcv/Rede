import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ReaderWindowStore {
    struct OpenResult {
        let open: UUID
        let dismiss: [UUID]
    }

    private static let restorableBooksKey = "Rede.RestorableBooks"

    private var sessions: [UUID: ReaderSession] = [:]
    private var order: [UUID] = []
    private var hasRestored = false

    func session(for id: UUID) -> ReaderSession? {
        sessions[id]
    }

    func open(_ book: Book, context: ModelContext, mode: ReaderWindowMode) throws -> OpenResult {
        if let existingID = sessions.first(where: { $0.value.book?.id == book.id })?.key {
            let dismiss = mode == .single ? closeAll(except: existingID) : []
            promote(existingID)
            return OpenResult(open: existingID, dismiss: dismiss)
        }

        if mode == .single, let reuseID = preferredWindowID, let session = sessions[reuseID] {
            try session.open(book, context: context)
            let dismiss = closeAll(except: reuseID)
            promote(reuseID)
            return OpenResult(open: reuseID, dismiss: dismiss)
        }

        let session = ReaderSession()
        try session.open(book, context: context)
        let id = UUID()
        sessions[id] = session
        order.append(id)
        return OpenResult(open: id, dismiss: [])
    }

    func close(windowID: UUID) {
        sessions.removeValue(forKey: windowID)?.close()
        order.removeAll { $0 == windowID }
    }

    func close(bookID: Book.ID) -> UUID? {
        guard let windowID = sessions.first(where: { $0.value.book?.id == bookID })?.key else {
            return nil
        }
        close(windowID: windowID)
        return windowID
    }

    func setForeground(_ foreground: Bool, for windowID: UUID) {
        sessions[windowID]?.setForeground(foreground)
        if foreground, sessions[windowID] != nil {
            promote(windowID)
        }
    }

    func saveOpenBooks() {
        let ids = order.compactMap { sessions[$0]?.book?.id }
        UserDefaults.standard.set(ids, forKey: Self.restorableBooksKey)
    }

    func takeRestorableBookIDs(mode: ReaderWindowMode) -> [Book.ID] {
        guard !hasRestored else { return [] }
        hasRestored = true
        let ids = UserDefaults.standard.stringArray(forKey: Self.restorableBooksKey) ?? []
        UserDefaults.standard.removeObject(forKey: Self.restorableBooksKey)
        guard Settings.shared.restoreReaderWindows, sessions.isEmpty, !ids.isEmpty else {
            return []
        }
        return mode == .single ? Array(ids.suffix(1)) : ids
    }

    func flushAll() {
        for session in sessions.values {
            session.flush()
        }
    }

    private var preferredWindowID: UUID? {
        order.last { sessions[$0] != nil }
    }

    private func promote(_ id: UUID) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private func closeAll(except keepID: UUID) -> [UUID] {
        let others = order.filter { $0 != keepID }
        for id in others {
            sessions.removeValue(forKey: id)?.close()
        }
        order.removeAll { $0 != keepID }
        return others
    }
}
