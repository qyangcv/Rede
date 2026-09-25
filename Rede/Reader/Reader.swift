import WebKit
import UniformTypeIdentifiers

final class EpubSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "epub"
    static let host = "book"

    let book: EpubBook
    private let mediaTypes: [String: String]

    init(book: EpubBook) {
        self.book = book
        self.mediaTypes = Dictionary(
            book.model.manifest.values.map { ($0.path, $0.mediaType) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func url(for path: String, fragment: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + path
        components.fragment = fragment
        return components.url
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let path = String(url.path(percentEncoded: false).dropFirst())

        do {
            let data = try book.fetcher.data(at: path)
            let response = URLResponse(url: url,
                                       mimeType: mimeType(for: path),
                                       expectedContentLength: data.count,
                                       textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { }

    private func mimeType(for path: String) -> String {
        if let type = mediaTypes[path] { return type }
        let ext = (path as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }
}

final class AppResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "rede"
    private static let host = "app"
    private static let allowed: Set<String> = [
        "reader.html", "reader.js", "reader.css", "leaf.svg",
        "ReadiumCSS-before.css", "ReadiumCSS-default.css", "ReadiumCSS-after.css",
    ]

    static func url(for name: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + name
        return components.url
    }

    static func data(named name: String) throws -> Data {
        guard allowed.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: nil)
        else { throw URLError(.fileDoesNotExist) }
        return try Data(contentsOf: url)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let name = String(url.path(percentEncoded: false).dropFirst())
        do {
            let data = try Self.data(named: name)
            let ext = (name as NSString).pathExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(url: url, mimeType: mime,
                                       expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

final class Reader: NSObject,  WKNavigationDelegate {
    let book: EpubBook
    let webView: ReaderWebView

    private let bridge: JSBridge
    private var shellNavigation: WKNavigation?
    private var style = ReaderStyle.default

    static let progressChannel = "reading_progress"
    private let start: ReadingPosition?
    var onProgress: ((ReadingPosition) -> Void)?
    
    init(book: EpubBook, start: ReadingPosition? = nil) {
        self.book = book
        self.start = start
        
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(EpubSchemeHandler(book: book), forURLScheme: EpubSchemeHandler.scheme)
        config.setURLSchemeHandler(AppResourceSchemeHandler(), forURLScheme: AppResourceSchemeHandler.scheme)

        let relay = ProgressRelay()
        config.userContentController.add(relay, name: Self.progressChannel)
        
        self.webView = ReaderWebView(frame: .zero, configuration: config)
        
        #if DEBUG
        self.webView.isInspectable = true
        #endif
        
        self.bridge = JSBridge(webView: webView)
        
        super.init()

        relay.reader = self
        webView.navigationDelegate = self
        webView.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
    }

    func open(style: ReaderStyle) {
        self.style = style
        guard let baseURL = EpubSchemeHandler.url(for: ""),
              let html = try? AppResourceSchemeHandler.data(named: "reader.html") else { return }
        shellNavigation = webView.load(html, mimeType: "text/html",
                                       characterEncodingName: "utf-8", baseURL: baseURL)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === shellNavigation else { return }
        let paths = book.model.spine.map(\.path)
        let language = book.model.metadata.language
        let style = style.cssVariables
        Task { await bridge.open(paths: paths, language: language, style: style, start: start) }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return .allow }

        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    func apply(_ style: ReaderStyle) {
        self.style = style
        Task { await bridge.setStyle(style.cssVariables) }
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
              let key = event.specialKey else { return false }

        switch key {
        case .leftArrow: Task { await bridge.prev() }
        case .rightArrow: Task { await bridge.next() }
        default: return false
        }
        return true
    }

    func go(to entry: EpubTocEntry) {
        guard let index = book.model.spine.firstIndex(where: { $0.path == entry.path }) else { return }
        Task {
            await bridge.jump(chapter: index, anchor: entry.fragment)
            webView.window?.makeFirstResponder(webView)
        }
    }
}

private final class ProgressRelay: NSObject, WKScriptMessageHandler {
    weak var reader: Reader?

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let data = try? JSONSerialization.data(withJSONObject: message.body),
              let position = try? JSONDecoder().decode(ReadingPosition.self, from: data)
        else { return }
        reader?.onProgress?(position)
    }
}
