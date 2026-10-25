import SwiftUI

struct BookTable<Menu: View>: View {
    let books: [Book]
    let readingTimes: [Book.ID: Duration]
    @Binding var sort: LibrarySort
    @Binding var order: SortOrder
    @Binding var selection: Set<Book.ID>
    let open: (Book) -> Void
    @ViewBuilder let menu: (Set<Book.ID>) -> Menu

    @SceneStorage("BookTableColumns") private var columns = TableColumnCustomization<Book>()

    private var sortOrder: Binding<[BookComparator]> {
        Binding {
            [BookComparator(key: sort, order: order, readingTimes: readingTimes)]
        } set: {
            guard let first = $0.first else { return }
            sort = first.key
            order = first.order
        }
    }

    private func comparator(_ key: LibrarySort) -> BookComparator {
        BookComparator(key: key, order: key.defaultOrder, readingTimes: readingTimes)
    }

    var body: some View {
        Table(books, selection: $selection, sortOrder: sortOrder, columnCustomization: $columns) {
            TableColumn("书名", sortUsing: comparator(.title)) { book in
                Text(book.name).help(book.name)
            }
            .width(min: 160, ideal: 280)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("作者", sortUsing: comparator(.author)) { book in
                Text(book.author)
            }
            .width(min: 80, ideal: 140)
            .customizationID("author")

            TableColumn("字数", sortUsing: comparator(.wordCount)) { book in
                if let count = book.wordCount {
                    Text(count.formatted()).monospacedDigit()
                }
            }
            .width(min: 60, ideal: 80)
            .alignment(.numeric)
            .customizationID("wordCount")

            TableColumn("最近阅读", sortUsing: comparator(.lastRead)) { book in
                if let date = book.lastRead {
                    Text(date.formatted(date: .numeric, time: .shortened)).monospacedDigit()
                }
            }
            .width(min: 110, ideal: 130)
            .customizationID("lastRead")

            TableColumn("进度", sortUsing: comparator(.progress)) { book in
                if let text = book.progressText {
                    Text(text).monospacedDigit()
                }
            }
            .width(min: 50, ideal: 60)
            .alignment(.numeric)
            .customizationID("progress")

            TableColumn("阅读时长", sortUsing: comparator(.readingTime)) { book in
                if let text = readingTimes[book.id]?.readingText {
                    Text(text)
                }
            }
            .width(min: 70, ideal: 100)
            .alignment(.trailing)
            .customizationID("readingTime")
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: Book.ID.self, menu: menu) { ids in
            guard ids.count == 1, let book = books.first(where: { ids.contains($0.id) }) else { return }
            open(book)
        }
    }
}
