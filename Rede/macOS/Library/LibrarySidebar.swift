import AppKit
import SwiftUI

enum LibrarySection: Hashable {
    case library
    case category(UUID)
}

struct LibrarySidebar: View {
    struct Category: Equatable {
        let id: UUID
        let name: String
    }

    let categories: [Category]
    @Binding var selection: LibrarySection?
    let createCategory: () -> Void
    let renameCategory: (UUID) -> Void
    let deleteCategory: (UUID) -> Void
    let moveCategories: (IndexSet, Int) -> Bool
    let importFiles: ([URL], LibrarySection) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarOutline(sidebar: self)
            HStack {
                Button(action: createCategory) {
                    Label("新建分类", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .help("新建分类")

                Spacer()

                SidebarSyncStatus()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }
}

private struct SidebarSyncStatus: View {
    private enum Phase {
        case syncing, done

        var title: String { self == .syncing ? "正在从 iCloud 同步" : "已同步" }
        var symbol: String { self == .syncing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud" }
    }

    @State private var phase: Phase?
    @State private var isPresented = false

    private var monitor: SyncMonitor { .shared }

    var body: some View {
        ZStack {
            if monitor.hasProblem {
                Button { isPresented.toggle() } label: {
                    Label("iCloud 同步出错", systemImage: "exclamationmark.icloud")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .help("iCloud 同步出错")
                .popover(isPresented: $isPresented, arrowEdge: .top) {
                    Text(monitor.summary)
                        .frame(maxWidth: 260, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                }
            } else if let phase {
                Image(systemName: phase.symbol)
                    .imageScale(.large)
                    .symbolEffect(.rotate.byLayer, isActive: phase == .syncing)
                    .id(phase)
                    .transition(.symbolEffect(.drawOn))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 28, height: 28)
                    .help(phase.title)
                    .accessibilityLabel(phase.title)
            }
        }
        .frame(width: 28, height: 28)
        .animation(.default, value: phase)
        .animation(.default, value: monitor.hasProblem)
        .onChange(of: monitor.hasProblem) { _, hasProblem in
            if !hasProblem { isPresented = false }
        }
        .task(id: monitor.isImporting) {
            if monitor.isImporting { phase = .syncing; return }
            guard phase == .syncing else { return }
            guard !monitor.hasProblem else { phase = nil; return }
            do {
                try await Task.sleep(for: .seconds(1))
                guard !monitor.hasProblem else { phase = nil; return }
                phase = .done
                try await Task.sleep(for: .seconds(2))
                phase = nil
            } catch {}
        }
    }
}

private struct SidebarOutline: NSViewRepresentable {
    let sidebar: LibrarySidebar

    func makeCoordinator() -> Coordinator {
        Coordinator(sidebar: sidebar)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outline = coordinator.outline
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LibrarySidebar"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.autoresizingMask = [.width]
        outline.setAccessibilityLabel("书库侧边栏")
        outline.registerForDraggedTypes([Coordinator.categoryPasteboardType, .fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)

        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.menuForRow = { [weak coordinator, weak outline] row in
            guard let outline else { return nil }
            return coordinator?.menu(for: outline.item(atRow: row))
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = outline

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(sidebar: sidebar)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        fileprivate static let categoryPasteboardType = NSPasteboard.PasteboardType("dev.qyang.Rede.library-category")
        private static let itemCellID = NSUserInterfaceItemIdentifier("LibrarySidebarItem")
        private static let headingCellID = NSUserInterfaceItemIdentifier("LibrarySidebarHeading")

        let outline = SidebarOutlineView()
        private var sidebar: LibrarySidebar
        private let library = SidebarItem(section: .library, name: BookCategories.libraryName)
        private let heading = SidebarItem(section: nil, name: "分类")
        private var items: [SidebarItem] = []
        private var categoryItems: [UUID: SidebarItem] = [:]
        private var displayedCategories: [LibrarySidebar.Category]?
        private var isUpdating = false

        init(sidebar: LibrarySidebar) {
            self.sidebar = sidebar
        }

        func update(sidebar: LibrarySidebar) {
            self.sidebar = sidebar
            isUpdating = true
            defer { isUpdating = false }

            if displayedCategories != sidebar.categories {
                var updatedItems: [SidebarItem] = []
                let categoryRows = sidebar.categories.map { category in
                    let item = categoryItems[category.id] ?? SidebarItem(section: .category(category.id), name: category.name)
                    if item.name != category.name {
                        item.name = category.name
                        updatedItems.append(item)
                    }
                    return item
                }
                categoryItems = Dictionary(uniqueKeysWithValues: zip(sidebar.categories.map(\.id), categoryRows))
                items = [library, heading] + categoryRows

                if displayedCategories?.map(\.id) == sidebar.categories.map(\.id) {
                    for item in updatedItems { outline.reloadItem(item) }
                } else {
                    outline.reloadData()
                }
                displayedCategories = sidebar.categories
            }

            let row = sidebar.selection.flatMap { selection -> Int? in
                switch selection {
                case .library:
                    return outline.row(forItem: library)
                case .category(let id):
                    return categoryItems[id].map { outline.row(forItem: $0) }
                }
            } ?? -1
            if row != outline.selectedRow {
                if row >= 0 {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                } else {
                    outline.deselectAll(nil)
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            item == nil ? items.count : 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            items[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            false
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            (item as? SidebarItem) === heading
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? SidebarItem)?.section != nil
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let outline = notification.object as? NSOutlineView else { return }
            let row = outline.selectedRow
            let selection = row >= 0 ? (outline.item(atRow: row) as? SidebarItem)?.section : nil
            if sidebar.selection != selection { sidebar.selection = selection }
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            guard (item as? SidebarItem)?.section != nil else { return nil }
            return SidebarRowView()
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? SidebarItem else { return nil }
            guard let section = item.section else {
                return outlineView.makeView(withIdentifier: Self.headingCellID, owner: nil) ?? makeHeadingCell()
            }

            let cell = outlineView.makeView(withIdentifier: Self.itemCellID, owner: nil) as? NSTableCellView
                ?? makeItemCell()
            cell.textField?.stringValue = item.name
            cell.imageView?.image = section == .library ? SidebarSymbols.library : SidebarSymbols.category
            return cell
        }

        fileprivate func menu(for item: Any?) -> NSMenu? {
            guard let row = item as? SidebarItem, case .category(let id) = row.section else { return nil }
            let menu = NSMenu()
            let rename = NSMenuItem(title: "重命名", action: #selector(renameCategory(_:)), keyEquivalent: "")
            rename.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            let delete = NSMenuItem(title: "删除分类", action: #selector(deleteCategory(_:)), keyEquivalent: "")
            delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            for action in [rename, delete] {
                action.target = self
                action.representedObject = id
                menu.addItem(action)
            }
            return menu
        }

        @objc private func renameCategory(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            sidebar.renameCategory(id)
        }

        @objc private func deleteCategory(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            sidebar.deleteCategory(id)
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let row = item as? SidebarItem, case .category(let id) = row.section else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(id.uuidString, forType: Self.categoryPasteboardType)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?, proposedChildIndex index: Int
        ) -> NSDragOperation {
            if info.draggingSource as? NSOutlineView === outlineView {
                return categoryMove(info, item: item, index: index) == nil ? [] : .move
            }

            guard !bookURLs(from: info.draggingPasteboard).isEmpty else { return [] }
            let point = outlineView.convert(info.draggingLocation, from: nil)
            let row = outlineView.row(at: point)
            guard row >= 0, let target = outlineView.item(atRow: row) as? SidebarItem,
                  target.section != nil else { return [] }
            outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int
        ) -> Bool {
            if info.draggingSource as? NSOutlineView === outlineView {
                guard let move = categoryMove(info, item: item, index: index) else { return false }
                return sidebar.moveCategories(IndexSet(integer: move.source), move.destination)
            }

            guard index == NSOutlineViewDropOnItemIndex, let section = (item as? SidebarItem)?.section else { return false }
            let urls = bookURLs(from: info.draggingPasteboard)
            return !urls.isEmpty && sidebar.importFiles(urls, section)
        }

        private func categoryMove(_ info: any NSDraggingInfo, item: Any?, index: Int) -> (source: Int, destination: Int)? {
            guard item == nil, let headingIndex = items.firstIndex(where: { $0 === heading }),
                  index > headingIndex, index <= items.count,
                  let value = info.draggingPasteboard.string(forType: Self.categoryPasteboardType),
                  let id = UUID(uuidString: value),
                  let source = sidebar.categories.firstIndex(where: { $0.id == id }) else { return nil }
            let destination = index - headingIndex - 1
            guard destination != source, destination != source + 1 else { return nil }
            return (source, destination)
        }

        private func bookURLs(from pasteboard: NSPasteboard) -> [URL] {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.filter(BookImporter.supports)
        }

        private func makeItemCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = Self.itemCellID

            let icon = NSImageView()
            icon.imageScaling = .scaleProportionallyDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon

            let title = NSTextField(labelWithString: "")
            title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(title)
            cell.textField = title

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(lessThanOrEqualTo: cell.heightAnchor),
                title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func makeHeadingCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = Self.headingCellID
            let title = NSTextField(labelWithString: heading.name)
            title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(title)
            cell.textField = title
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

private final class SidebarItem: NSObject {
    let section: LibrarySection?
    var name: String

    init(section: LibrarySection?, name: String) {
        self.section = section
        self.name = name
    }
}

private final class SidebarOutlineView: NSOutlineView {
    var menuForRow: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        menu = row >= 0 ? menuForRow?(row) : nil
        return super.menu(for: event)
    }
}

private final class SidebarRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set { super.isEmphasized = false }
    }
}

private enum SidebarSymbols {
    static let library = symbol(named: "books.vertical")
    static let category = symbol(named: "folder")

    private static func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium, scale: .large)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}
