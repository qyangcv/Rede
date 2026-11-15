import AppKit
import SwiftUI

enum LibrarySection: Hashable {
    case library
    case category(UUID)
}

struct LibrarySidebar: NSViewRepresentable {
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
    let importEPUBs: ([URL], LibrarySection) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(sidebar: self)
    }

    func makeNSView(context: Context) -> SidebarContentView {
        let sidebarView = SidebarContentView()
        let outline = sidebarView.outline
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

        let coordinator = context.coordinator
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

        let add = NSButton()
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageOnly
        add.isBordered = false
        add.target = coordinator
        add.action = #selector(Coordinator.createCategory(_:))
        add.toolTip = "新建分类"
        add.setAccessibilityLabel("新建分类")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        add.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(scrollView)
        sidebarView.addSubview(add)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -4),
            add.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 8),
            add.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -6),
            add.widthAnchor.constraint(equalToConstant: 28),
            add.heightAnchor.constraint(equalToConstant: 28)
        ])
        return sidebarView
    }

    func updateNSView(_ sidebarView: SidebarContentView, context: Context) {
        context.coordinator.update(sidebar: self, in: sidebarView.outline)
    }

    final class SidebarContentView: NSView {
        fileprivate let outline = SidebarOutlineView()
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        fileprivate static let categoryPasteboardType = NSPasteboard.PasteboardType("dev.qyang.Rede.library-category")
        private static let itemCellID = NSUserInterfaceItemIdentifier("LibrarySidebarItem")
        private static let headingCellID = NSUserInterfaceItemIdentifier("LibrarySidebarHeading")

        private var sidebar: LibrarySidebar
        private let library = SidebarItem(section: .library, name: BookCategories.libraryName)
        private let heading = SidebarItem(section: nil, name: "分类")
        private var items: [SidebarItem] = []
        private var categoryItems: [UUID: SidebarItem] = [:]
        private var displayedCategories: [Category]?
        private var isUpdating = false

        init(sidebar: LibrarySidebar) {
            self.sidebar = sidebar
        }

        func update(sidebar: LibrarySidebar, in outline: NSOutlineView) {
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

        @objc fileprivate func createCategory(_ sender: NSButton) {
            sidebar.createCategory()
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

            guard !epubURLs(from: info.draggingPasteboard).isEmpty else { return [] }
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
            let urls = epubURLs(from: info.draggingPasteboard)
            return !urls.isEmpty && sidebar.importEPUBs(urls, section)
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

        private func epubURLs(from pasteboard: NSPasteboard) -> [URL] {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.filter { $0.pathExtension.lowercased() == "epub" }
        }

        private func makeItemCell() -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = Self.itemCellID

            let icon = NSImageView()
            icon.imageScaling = .scaleProportionallyDown
            icon.contentTintColor = NSColor(srgbRed: 154.0 / 255, green: 109.0 / 255, blue: 46.0 / 255, alpha: 1)
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
