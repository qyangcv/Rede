import WebKit
import os

struct JSBridge {
    private static let log = Logger(subsystem: "MyReader", category: "JSBridge")
    let webView: WKWebView

    @discardableResult
    func call(_ body: String, _ arguments: [String: Any] = [:]) async -> Any? {
        do {
            return try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
        } catch {
            Self.log.error("\(body, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension JSBridge {
    func open(paths: [String], style: [String: String], start: ReadingPosition?) async {
        await call("reader.open(paths, style, start)",
                   ["paths": paths, "style": style, "start": start?.jsObject ?? NSNull()])
    }
    func setStyle(_ vars: [String: String]) async {
        await call("reader.setStyle(vars)", ["vars": vars])
    }
    func next() async {
        await call("reader.next()") 
    }
    func prev() async {
        await call("reader.prev()") 
    }
    func jump(chapter: Int, anchor: String?) async 
    {
        await call("reader.jump(chapter, anchor)", ["chapter": chapter, "anchor": anchor ?? ""])
    }
}
