import WebKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        if name == "fonts.css" { return Data(ReaderFont.fontFaceCSS.utf8) }
        if let url = ReaderFont.fontFile(at: name) { return try Data(contentsOf: url, options: .mappedIfSafe) }
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
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": name.hasPrefix("fonts/") ? mime : "\(mime); charset=utf-8",
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*",
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

// 阅读区的输入：点击由 reader.js 识别后上报，按键由各平台的 WebView 识别；怎样响应由各平台决定
enum ReaderGesture {
    case tap(x: Double)        // 点击位置占 WebView 宽度的比例，0 为最左
    case turn(PageDirection)   // 方向键等要求翻页
}

final class Reader: NSObject,  WKNavigationDelegate {
    let book: EpubBook
    let webView: ReaderWebView
    let toc: [TOCItem]
    private let spineIndex: [String: Int]

    private let bridge: JSBridge
    private var shellNavigation: WKNavigation?
    private var style: [String: String] = [:]

    static let progressChannel = "reading_progress"
    static let gestureChannel = "gesture"

    private(set) var position: ReadingPosition?
    
    var onProgress: ((ReadingPosition, PageInfo, TOCItem?) -> Void)?
    var onGesture: ((ReaderGesture) -> Void)?
    var onTurn: (() -> Void)?
    
    private(set) var navigated = false
    
    init(book: EpubBook, start: ReadingPosition? = nil) {
        self.book = book
        self.position = start
        self.toc = TOCItem.flatten(book.model.toc)
        self.spineIndex = Dictionary(book.model.spine.enumerated().map { ($1.path, $0) },
                                     uniquingKeysWith: { first, _ in first })
        
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(EpubSchemeHandler(book: book), forURLScheme: EpubSchemeHandler.scheme)
        config.setURLSchemeHandler(AppResourceSchemeHandler(), forURLScheme: AppResourceSchemeHandler.scheme)

        let relay = MessageRelay()
        config.userContentController.add(relay, name: Self.progressChannel)
        config.userContentController.add(relay, name: Self.gestureChannel)
        
        self.webView = ReaderWebView(frame: .zero, configuration: config)
        
        #if DEBUG
        self.webView.isInspectable = true
        #endif
        
        self.bridge = JSBridge(webView: webView)
        
        super.init()

        relay.reader = self
        webView.navigationDelegate = self
    }

    func open(style: [String: String]) {
        self.style = style
        guard let baseURL = EpubSchemeHandler.url(for: ""),
              let html = try? AppResourceSchemeHandler.data(named: "reader.html") else { return }
        injectInitialStyle(style)
        shellNavigation = webView.load(html, mimeType: "text/html",
                                       characterEncodingName: "utf-8", baseURL: baseURL)
    }
    
    private func injectInitialStyle(_ style: [String: String]) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        let json = String(decoding: data, as: UTF8.self)
        let source = """
            for (const [name, value] of Object.entries(\(json)))
              document.documentElement.style.setProperty(name, value);
            """
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === shellNavigation else { return }
        let paths = book.model.spine.map(\.path)
        let language = book.model.metadata.language
        let style = style
        let tocAnchors = book.model.spine.map { item in
            toc.compactMap { $0.entry.path == item.path ? $0.entry.fragment : nil }
        }
        Task {
            await bridge.open(paths: paths, language: language, style: style, start: position,
                              tocAnchors: tocAnchors)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        open(style: style)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return .allow }

        if navigationAction.navigationType == .linkActivated {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            #endif
        }
        return .cancel
    }

    func apply(_ style: [String: String]) {
        self.style = style
        Task { await bridge.setStyle(style) }
    }

    func go(to entry: EpubTocEntry) {
        guard let index = spineIndex[entry.path] else { return }
        navigated = true
        Task {
            await bridge.jump(chapter: index, anchor: entry.fragment)
            focus()
        }
    }
    
    // 前后翻 step 页
    func turn(_ step: Int) {
        navigated = true
        onTurn?()
        Task { await bridge.turn(step) }
    }

    // 仿真翻页翻完后，把主 WebView 同步到卷页层停下的那一页，等画好再返回
    func show(_ position: ReadingPosition) async {
        navigated = true
        onTurn?()
        await bridge.restore(position)
        await painted()
    }

    // 等页面渲染出两帧：刚翻页、刚落位时直接截图或显示，时常还是上一帧的画面
    private func painted() async {
        await bridge.call("await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))")
    }

    func snapshot() async -> PlatformImage? {
        await painted()
        return try? await webView.takeSnapshot(configuration: nil)
    }

    func restore(_ position: ReadingPosition) {
        Task { await bridge.restore(position) }
    }

    fileprivate func receive(_ report: ProgressReport) {
        position = report.position
        onProgress?(report.position, report.page, tocItem(at: report.position, anchors: report.anchors))
    }

    // 相邻页渲染器用：落到 position 再翻 step 页并截图；没有相邻页或被后续渲染打断时返回 nil
    func peek(from position: ReadingPosition, step: Int) async -> RenderedPage? {
        guard let report = await bridge.peek(from: position, step: step),
              let image = await snapshot() else { return nil }
        return RenderedPage(image: image, position: report.position, page: report.page,
                            chapter: tocItem(at: report.position, anchors: report.anchors))
    }

    private func tocItem(at position: ReadingPosition, anchors: [String: Int]) -> TOCItem? {
        let target = (position.chapter, position.offset < 0 ? Int.max : position.offset)
        let keys = toc.indices.compactMap { i -> (Int, Int, Int)? in
            let entry = toc[i].entry
            guard let spine = spineIndex[entry.path] else { return nil }
            return (spine, entry.fragment.flatMap { anchors[$0] } ?? 0, i)
        }
        return keys.filter { ($0.0, $0.1) <= target }.max { $0 < $1 }.map { toc[$0.2] }
    }
}

private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var reader: Reader?

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case Reader.progressChannel: receiveProgress(message.body)
        case Reader.gestureChannel: receiveGesture(message.body)
        default: break
        }
    }

    private func receiveProgress(_ body: Any) {
        guard let report = ProgressReport(body) else { return }
        reader?.receive(report)
    }

    private func receiveGesture(_ body: Any) {
        guard let body = body as? [String: Any] else { return }
        let gesture: ReaderGesture? = switch body["type"] as? String {
        case "tap": (body["x"] as? Double).map { .tap(x: $0) }
        default: nil
        }
        if let gesture { reader?.onGesture?(gesture) }
    }
}
