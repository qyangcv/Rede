import SwiftUI

struct LibraryMenuContext {
    let columnVisibility: Binding<NavigationSplitViewVisibility>
    let beginImport: () -> Void
    let createCategory: () -> Void
    let open: (() -> Void)?
    let showInfo: (() -> Void)?
    let editInfo: (() -> Void)?
    let export: (() -> Void)?
    let delete: (() -> Void)?
    let category: Category?

    struct Category {
        let categories: [BookCategory]
        let currentCategory: UUID?
        let canRemove: Bool
        let assign: (BookCategory?) -> Void
        let create: () -> Void
    }
}

extension FocusedValues {
    @Entry var libraryMenuContext: LibraryMenuContext?
}

private struct LibraryCategoryMenu: View {
    let context: LibraryMenuContext.Category?

    var body: some View {
        Menu("移至分类", systemImage: "folder") {
            if let context, !context.categories.isEmpty {
                ForEach(context.categories) { category in
                    Toggle(category.name, isOn: Binding(
                        get: { context.currentCategory == category.id },
                        set: { context.assign($0 ? category : nil) }
                    ))
                }
                Divider()
            }

            Button("移出分类") { context?.assign(nil) }
                .disabled(context?.canRemove != true)
            Button("新建分类") { context?.create() }
                .disabled(context == nil)
        }
        .disabled(context == nil)
    }
}

struct LibraryBookContextMenu: View {
    let selectionCount: Int
    let context: LibraryMenuContext

    var body: some View {
        if selectionCount > 1 {
            LibraryCategoryMenu(context: context.category)
            Button("导出 \(selectionCount) 本", systemImage: "square.and.arrow.up") { context.export?() }
            Button("从书库删除 \(selectionCount) 本", systemImage: "trash", role: .destructive) {
                context.delete?()
            }
        } else if let open = context.open {
            Button("阅读", systemImage: "book", action: open)
            LibraryCategoryMenu(context: context.category)
            Button("显示书籍简介", systemImage: "info.circle") { context.showInfo?() }
            Button("编辑书籍信息", systemImage: "pencil") { context.editInfo?() }
            Button("导出 EPUB", systemImage: "square.and.arrow.up") { context.export?() }
            Button("从书库删除", systemImage: "trash", role: .destructive) { context.delete?() }
        }
    }
}

struct LibraryFileCommands: View {
    @FocusedValue(\.libraryMenuContext) private var context

    var body: some View {
        Button("导入 EPUB") { context?.beginImport() }
            .disabled(context == nil)
        Button("打开") { context?.open?() }
            .disabled(context?.open == nil)

        Divider()

        Button("新建分类") { context?.createCategory() }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(context == nil)
        LibraryCategoryMenu(context: context?.category)

        Divider()

        Button("显示简介") { context?.showInfo?() }
            .disabled(context?.showInfo == nil)
        Button("编辑信息") { context?.editInfo?() }
            .disabled(context?.editInfo == nil)
        Button("导出") { context?.export?() }
            .disabled(context?.export == nil)
        Button("删除", role: .destructive) { context?.delete?() }
            .disabled(context?.delete == nil)
    }
}

struct OpenLibraryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示书库") {
            openWindow(id: RedeApp.libraryWindowID)
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}

struct LibraryDisplayCommands: View {
    static let layoutMenuTitle = "陈列方式"

    @FocusedValue(\.libraryMenuContext) private var context
    @Bindable private var settings = Settings.shared

    private var sort: Binding<LibrarySort> {
        Binding {
            settings.librarySort
        } set: { key in
            guard settings.librarySort != key else { return }
            settings.librarySort = key
            settings.libraryOrder = key.defaultOrder
        }
    }

    var body: some View {
        Menu(Self.layoutMenuTitle) {
            Picker(Self.layoutMenuTitle, selection: $settings.libraryLayout) {
                Text(LibraryLayout.grid.name).tag(LibraryLayout.grid).keyboardShortcut("1")
                Text(LibraryLayout.list.name).tag(LibraryLayout.list).keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(context == nil)

        Menu("排序") {
            Picker("排序依据", selection: sort) {
                ForEach(LibrarySort.allCases) { key in
                    Text(key.name).tag(key)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("排序顺序", selection: $settings.libraryOrder) {
                Text("升序").tag(SortOrder.forward)
                Text("降序").tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        }
        .disabled(context == nil)

        Divider()

        Button(context?.columnVisibility.wrappedValue == .detailOnly ? "显示侧边栏" : "隐藏侧边栏") {
            guard let visibility = context?.columnVisibility else { return }
            visibility.wrappedValue = visibility.wrappedValue == .detailOnly ? .all : .detailOnly
        }
        .keyboardShortcut(context == nil ? nil : KeyboardShortcut("b"))
        .disabled(context == nil)
    }
}
