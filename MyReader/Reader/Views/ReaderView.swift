import SwiftUI
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
    
    var body: some View {
        ReaderWebViewContainer(webView: reader.webView)
            .overlay (alignment: .bottomLeading) {
                TOCButton(toc: reader.book.model.toc, onSelect: reader.go(to:))
            }
            .onAppear { reader.open() }
    }
}

@Observable
final class ReaderSession {
    static let windowID = "reader"
    
    private(set) var reader: Reader?
    private(set) var bookName: String?
    
    func open(_ book: Book) throws {
        if bookName == book.name, reader != nil { return }
        let epub = try parseEpub(at: book.url)
        reader = Reader(book: epub)
        bookName = book.name
    }
    
    func close() {
        reader = nil
        bookName = nil
    }
}

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session

    var body: some View {
        ZStack {
            if let reader = session.reader {
                ReaderView(reader: reader)
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .navigationTitle(session.bookName ?? "Reader Window")
        .onDisappear { session.close() }
    }
}
