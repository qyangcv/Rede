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
    static let scheme = "myreader"
    private static let host = "app"
    private static let allowed: Set<String> = ["reader.html", "reader.js", "reader.css", "leaf.svg"]

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
    
    init(book: EpubBook) {
        self.book = book
        
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(EpubSchemeHandler(book: book), forURLScheme: EpubSchemeHandler.scheme)
        config.setURLSchemeHandler(AppResourceSchemeHandler(), forURLScheme: AppResourceSchemeHandler.scheme)
        
        self.webView = ReaderWebView(frame: .zero, configuration: config)
        self.webView.isInspectable = true
        self.bridge = JSBridge(webView: webView)
        
        super.init()
        
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
        let style = style.cssVariables
        Task { await bridge.open(paths: paths, style: style) }
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
