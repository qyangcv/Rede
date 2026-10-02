import WebKit
import os

struct JSBridge {
    private static let log = Logger(subsystem: "Rede", category: "JSBridge")
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
    func open(paths: [String], language: String, style: [String: String], start: ReadingPosition?,
              tocAnchors: [[String]]) async {
        await call("reader.open(paths, language, style, start, tocAnchors)",
                   ["paths": paths, "language": language, "style": style,
                    "start": start?.jsObject ?? NSNull(), "tocAnchors": tocAnchors])
    }
    func setStyle(_ vars: [String: String]) async {
        await call("reader.setStyle(vars)", ["vars": vars])
    }
    func turn(_ step: Int) async {
        await call("reader.turn(step)", ["step": step])
    }
    func jump(chapter: Int, anchor: String?) async
    {
        await call("reader.jump(chapter, anchor)", ["chapter": chapter, "anchor": anchor ?? ""])
    }
    func restore(_ position: ReadingPosition) async {
        await call("return reader.restore(position)", ["position": position.jsObject])
    }
    func peek(from position: ReadingPosition, step: Int) async -> ProgressReport? {
        await call("return reader.peek(position, step)", ["position": position.jsObject, "step": step])
            .flatMap(ProgressReport.init)
    }
}
