import SwiftUI
import AppKit

@Observable
final class ReaderSearch {
    var query = ""
    private(set) var index: BookSearch?
    private(set) var hits: [BookSearch.Hit] = []
    private(set) var titles: [String] = []
    private(set) var failure: String?
    private(set) var searching = false
    private(set) var length = 0
    var selected: Int?
    var page = 0
    var scrollID: Int?
    var focusRequest = 0
    let pageSize = 50
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?

    func prepare(book: Book, reader: Reader) {
        guard index == nil, preparation == nil else { return }
        failure = nil
        preparation = Task {
            defer { preparation = nil }
            guard !Task.isCancelled else { return }
            await load(book: book, reader: reader)
        }
    }

    private func load(book: Book, reader: Reader) async {
        let names = Dictionary(reader.toc.map { ($0.entry.path, $0.entry.title) },
                               uniquingKeysWith: { first, _ in first })
        let spine = reader.book.model.spine
        titles = spine.enumerated().map { i, item in
            names[item.path].flatMap { $0.isEmpty ? nil : $0 } ?? "第 \(i + 1) 节"
        }
        do {
            let prepared = try await BookSearch.prepare(id: book.id, data: book.epubData(), spine: spine)
            try Task.checkCancellation()
            index = prepared
            runQuery()
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }

    func update(_ text: String, reader: Reader) {
        guard !text.utf16.elementsEqual(query.utf16) else { return }
        query = text
        reader.clearSearchHit()
        runQuery()
    }

    private func runQuery() {
        task?.cancel()
        selected = nil
        scrollID = nil
        page = 0
        hits = []
        length = query.utf16.count
        searching = false
        guard let index, !query.isEmpty else { return }
        searching = true
        task = Task { [query] in
            do {
                let result = try await index.search(query)
                try Task.checkCancellation()
                hits = result
                searching = false
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
                searching = false
            }
        }
    }

    func cancel() {
        preparation?.cancel()
        task?.cancel()
    }

    func adjacent(_ step: Int) -> Int? {
        guard !hits.isEmpty else { return nil }
        guard let selected else { return step > 0 ? 0 : hits.count - 1 }
        return (selected + step + hits.count) % hits.count
    }

    func select(_ row: Int) {
        selected = row
        page = row / pageSize
        scrollID = row
    }
}

struct ReaderSearchView: View {
    @Environment(\.pixelLength) private var pixelLength
    @Bindable var search: ReaderSearch
    let reader: Reader
    let onChoose: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BookSearchField(query: search.query, focusRequest: search.focusRequest,
                            onChange: { search.update($0, reader: reader) },
                            onSubmit: {
                                if !search.hits.isEmpty {
                                    onChoose(search.selected ?? search.page * search.pageSize)
                                }
                            }, onClose: onClose, onMove: { step in
                                if let row = search.adjacent(step) { search.select(row) }
                            })
                .frame(height: 26)
                .padding(10)
            Divider()
            searchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var searchContent: some View {
        if let failure = search.failure {
            ContentUnavailableView("无法搜索本书", systemImage: "exclamationmark.magnifyingglass",
                                   description: Text(failure))
        } else if search.index == nil || search.searching {
            ProgressView(search.index == nil ? "正在准备本书搜索…" : "正在查找…")
                .controlSize(.small)
        } else if search.query.isEmpty {
            Color.clear
        } else if search.hits.isEmpty {
            ContentUnavailableView.search(text: search.query)
        } else if let index = search.index {
            results(index)
        }
    }

    private func results(_ index: BookSearch) -> some View {
        let hits = search.hits
        let length = search.length
        let titles = search.titles
        let first = search.page * search.pageSize
        let limit = min(first + search.pageSize, hits.count)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(hits.count) 处匹配")
                Spacer()
                if hits.count > search.pageSize {
                    Text("\(first + 1)–\(limit)")
                    Button("上一组", systemImage: "chevron.left") { changePage(-1) }
                        .disabled(first == 0)
                    Button("下一组", systemImage: "chevron.right") { changePage(1) }
                        .disabled(limit == hits.count)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(first..<limit, id: \.self) { row in
                        let hit = hits[row]
                        VStack(alignment: .leading, spacing: 2) {
                            if row == first || hits[row - 1].chapter != hit.chapter {
                                HStack(spacing: 8) {
                                    Text(titles[hit.chapter])
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .layoutPriority(1)
                                        .accessibilityAddTraits(.isHeader)
                                    Rectangle()
                                        .fill(.separator)
                                        .frame(height: pixelLength)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 6)
                                .padding(.top, row == first ? 6 : 16)
                            } else {
                                Divider()
                                    .opacity(0.5)
                                    .padding(.horizontal, 6)
                            }
                            let s = index.snippet(hit, length: length)
                            Button { onChoose(row) } label: {
                                Text("\(s.before)\(Text(s.match).bold())\(s.after)")
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(search.selected == row ? Color.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .id(row)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 6)
            }
            .scrollPosition(id: $search.scrollID)
        }
    }

    private func changePage(_ step: Int) {
        search.select((search.page + step) * search.pageSize)
    }
}

private struct BookSearchField: NSViewRepresentable {
    let query: String
    let focusRequest: Int
    let onChange: (String) -> Void
    let onSubmit: () -> Void
    let onClose: () -> Void
    let onMove: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = "在本书中查找"
        field.setAccessibilityLabel("在本书中查找")
        field.delegate = context.coordinator
        field.stringValue = query
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.request != focusRequest {
            field.request = focusRequest
            field.focus()
        }
    }

    final class Field: NSSearchField {
        var request: Int?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focus()
        }

        func focus() {
            guard let window else { return }
            window.makeFirstResponder(self)
            selectText(nil)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: BookSearchField

        init(_ parent: BookSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onClose()
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            default: return false
            }
            return true
        }
    }
}
