import SwiftUI
import SwiftData
import WebKit

final class ReaderWebView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

struct ReaderWebViewContainer: NSViewRepresentable {
    let webView: ReaderWebView
    func makeNSView(context: Context) -> ReaderWebView { webView }
    func updateNSView(_ nsView: ReaderWebView, context: Context) {}
}

struct ReaderView: View {
    let reader: Reader
    let page: PageInfo?

    @Bindable private var settings = Settings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var cssVariables: [String: String] {
        settings.readerStyle.cssVariables(for: colorScheme)
    }

    var body: some View {
        ReaderWebViewContainer(webView: reader.webView)
            .overlay(alignment: .top) {
                    Color.clear
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .gesture(WindowDragGesture())
                        .allowsWindowActivationEvents(true)
                }
            .overlay(alignment: .bottom) {
                if let page {
                    Text("\(page.page + 1) / \(page.pageCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TOCButton(toc: reader.book.model.toc, onSelect: reader.go(to:))
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    StyleButton(style: $settings.readerStyle, appearance: $settings.appearance,
                                onDismiss: reader.focus)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onAppear { reader.open(style: cssVariables) }
            .onChange(of: cssVariables) { _, new in
                reader.apply(new)
            }
    }
}

@Observable
final class ReaderSession {
    static let windowID = "reader"
    
    private(set) var reader: Reader?
    private(set) var book: Book?
    private(set) var page: PageInfo?
    private var store: ProgressStore?
    
    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store?.flush() }
        }
    }
    
    func open(_ book: Book, context: ModelContext) throws {
        if self.book?.id == book.id, reader != nil { return }
        store?.flush()

        let epub = try parseEpub(at: book.url)
        // 早于字数统计功能导入的书，首次打开时在后台补算
        ChapterLengthIndexer.shared.ensure(book, in: context)
        let store = ProgressStore(book: book, context: context)
        let reader = Reader(book: epub, start: book.position)
        reader.onProgress = { [weak self] position, page in
            MainActor.assumeIsolated {
                store.record(position)
                self?.page = page
            }
        }

        self.store = store
        self.reader = reader
        self.book = book
        self.page = nil
    }

    func close() {
        store?.flush()
        store = nil
        reader = nil
        book = nil
        page = nil
    }
}

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session

    var body: some View {
        ZStack {
            if let reader = session.reader {
                ReaderView(reader: reader, page: session.page)
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .ignoresSafeArea()
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(session.book?.name ?? "Reader Window")
        .onDisappear { session.close() }
    }
}
