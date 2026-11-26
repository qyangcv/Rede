import SwiftData
import SwiftUI

enum LibraryCategoryPanel: Hashable, Identifiable {
    case manage
    case move([Book.ID])

    var id: Self { self }
}

struct LibraryCategories: View {
    let panel: LibraryCategoryPanel
    let onMove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: BookCategories.sortDescriptors) private var categories: [BookCategory]
    @Query private var books: [Book]
    @State private var isNaming = false
    @State private var renaming: BookCategory?
    @State private var name = ""
    @State private var deleting: BookCategory?
    @State private var error: String?

    init(panel: LibraryCategoryPanel, onMove: @escaping () -> Void) {
        self.panel = panel
        self.onMove = onMove
        let ids: [Book.ID]
        switch panel {
        case .manage: ids = []
        case .move(let selection): ids = selection
        }
        _books = Query(filter: #Predicate<Book> { ids.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            List {
                switch panel {
                case .manage:
                    Section {
                        ForEach(categories) { category in
                            managementRow(category)
                        }
                        .onMove(perform: reorder)
                    }
                case .move:
                    let selection = BookCategories.Selection(books)
                    Section {
                        ForEach(categories) { category in
                            Button {
                                assign(to: category)
                            } label: {
                                HStack {
                                    Text(category.name)
                                    Spacer()
                                    if selection.commonID == category.id {
                                        Image(systemName: "checkmark")
                                            .accessibilityLabel("当前分类")
                                    }
                                }
                            }
                        }
                    }
                    if selection.canRemove {
                        Button("从分类中移除", systemImage: "folder.badge.minus") { assign(to: nil) }
                    }
                    Section {
                        newCategoryButton
                    }
                }
            }
            .navigationTitle(panel == .manage ? "管理分类" : "移至分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(panel == .manage ? "完成" : "取消") { dismiss() }
                }
                if panel == .manage {
                    ToolbarItem(placement: .primaryAction) {
                        newCategoryButton
                    }
                }
            }
            .alert(renaming == nil ? "新建分类" : "重命名分类", isPresented: $isNaming) {
                TextField("分类名称", text: $name)
                Button("取消", role: .cancel) {}
                Button(renaming == nil ? "创建" : "保存", action: saveName)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("删除分类“\(deleting?.name ?? "")”？",
                   isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                   presenting: deleting) { category in
                Button("删除分类", role: .destructive) {
                    do { try BookCategories.remove(category, from: modelContext) }
                    catch { self.error = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("书籍仍会保留在“我的书库”中。")
            }
            .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") {}
            } message: { Text(error ?? "") }
        }
        .onChange(of: books.isEmpty, initial: true) {
            if case .move = panel, books.isEmpty { dismiss() }
        }
    }

    private var newCategoryButton: some View {
        Button("新建分类", systemImage: "plus") { beginNaming(nil) }
    }

    private func managementRow(_ category: BookCategory) -> some View {
        HStack(spacing: 0) {
            Button { beginNaming(category) } label: {
                HStack(spacing: 8) {
                    Text(category.name)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .contentShape(.rect)
            }
            .accessibilityLabel("重命名分类，\(category.name)")

            Button { deleting = category } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("删除分类，\(category.name)")
        }
        .buttonStyle(.plain)
        .listRowInsets(.vertical, 4)
    }

    private func beginNaming(_ category: BookCategory?) {
        renaming = category
        name = category?.name ?? ""
        isNaming = true
    }

    private func saveName() {
        do {
            if let renaming {
                try BookCategories.rename(renaming, to: name, in: modelContext)
            } else {
                _ = try BookCategories.create(named: name, books: books, in: modelContext)
                if case .move = panel { finishMove() }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func assign(to category: BookCategory?) {
        do {
            try BookCategories.assign(books, to: category, in: modelContext)
            finishMove()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finishMove() {
        onMove()
        dismiss()
    }

    private func reorder(from offsets: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: offsets, toOffset: destination)
        do { try BookCategories.reorder(reordered, in: modelContext) }
        catch { self.error = error.localizedDescription }
    }
}
