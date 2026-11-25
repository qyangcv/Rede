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

    private var sessions: [UUID: ReaderSession] = [:]
    private var activeID: UUID?

    func session(for id: UUID) -> ReaderSession? {
        sessions[id]
    }

    func open(_ book: Book, context: ModelContext, mode: ReaderWindowMode) throws -> OpenResult {
        if let existingID = sessions.first(where: { $0.value.book?.id == book.id })?.key {
            let dismiss = mode == .single ? closeAll(except: existingID) : []
            activeID = existingID
            return OpenResult(open: existingID, dismiss: dismiss)
        }

        if mode == .single, let reuseID = preferredWindowID, let session = sessions[reuseID] {
            try session.open(book, context: context)
            let dismiss = closeAll(except: reuseID)
            activeID = reuseID
            return OpenResult(open: reuseID, dismiss: dismiss)
        }

        let session = ReaderSession()
        try session.open(book, context: context)
        let id = UUID()
        sessions[id] = session
        activeID = id
        return OpenResult(open: id, dismiss: [])
    }

    func close(windowID: UUID) {
        sessions.removeValue(forKey: windowID)?.close()
        if activeID == windowID {
            activeID = sessions.keys.first
        }
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
            activeID = windowID
        }
    }

    func flushAll() {
        for session in sessions.values {
            session.flush()
        }
    }

    private var preferredWindowID: UUID? {
        if let activeID, sessions[activeID] != nil { return activeID }
        return sessions.keys.first
    }

    private func closeAll(except keepID: UUID) -> [UUID] {
        let others = sessions.keys.filter { $0 != keepID }
        for id in others {
            sessions.removeValue(forKey: id)?.close()
        }
        return others
    }
}
