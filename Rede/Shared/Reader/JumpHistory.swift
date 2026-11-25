import Foundation
import Observation

struct JumpEntry: Identifiable, Equatable {
    let id: UUID
    let position: ReadingPosition
    let chapterTitle: String?
    let page: Int?
    let pageCount: Int?

    init(id: UUID = UUID(), position: ReadingPosition, chapterTitle: String?, page: Int?, pageCount: Int?) {
        self.id = id
        self.position = position
        self.chapterTitle = chapterTitle
        self.page = page
        self.pageCount = pageCount
    }
}

@Observable
final class JumpHistory {
    static let maxEntries = 50

    private(set) var backStack: [JumpEntry] = []
    private(set) var forwardStack: [JumpEntry] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var lastBack: JumpEntry? { backStack.last }
    var lastForward: JumpEntry? { forwardStack.last }

    func record(_ entry: JumpEntry) {
        push(entry, onto: &backStack)
        forwardStack.removeAll()
    }

    func goBack(from current: JumpEntry?) -> JumpEntry? {
        guard let target = backStack.popLast() else { return nil }
        if let current { push(current, onto: &forwardStack) }
        return target
    }

    func goForward(from current: JumpEntry?) -> JumpEntry? {
        guard let target = forwardStack.popLast() else { return nil }
        if let current { push(current, onto: &backStack) }
        return target
    }

    func goBack(to id: JumpEntry.ID, from current: JumpEntry?) -> JumpEntry? {
        guard let index = backStack.lastIndex(where: { $0.id == id }) else { return nil }
        if let current { push(current, onto: &forwardStack) }
        for entry in backStack[(index + 1)...].reversed() {
            push(entry, onto: &forwardStack)
        }
        let target = backStack[index]
        backStack.removeSubrange(index...)
        return target
    }

    func goForward(to id: JumpEntry.ID, from current: JumpEntry?) -> JumpEntry? {
        guard let index = forwardStack.lastIndex(where: { $0.id == id }) else { return nil }
        if let current { push(current, onto: &backStack) }
        for entry in forwardStack[(index + 1)...].reversed() {
            push(entry, onto: &backStack)
        }
        let target = forwardStack[index]
        forwardStack.removeSubrange(index...)
        return target
    }

    func clear() {
        backStack.removeAll()
        forwardStack.removeAll()
    }

    private func push(_ entry: JumpEntry, onto stack: inout [JumpEntry]) {
        if let last = stack.last, isSameLocation(last.position, entry.position) {
            stack[stack.count - 1] = entry
            return
        }
        stack.append(entry)
        if stack.count > Self.maxEntries {
            stack.removeFirst(stack.count - Self.maxEntries)
        }
    }

    private func isSameLocation(_ lhs: ReadingPosition, _ rhs: ReadingPosition) -> Bool {
        lhs.chapter == rhs.chapter && lhs.offset == rhs.offset
    }
}
