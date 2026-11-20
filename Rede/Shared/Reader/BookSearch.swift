import Foundation
import WebKit
import ZIPFoundation

nonisolated struct BookSearch {
    struct Passage: Codable {
        let start: Int
        let units: [UInt16]

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            start = try values.decode(Int.self)
            units = Array(try values.decode(String.self).utf16)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(start)
            try values.encode(String(decoding: units, as: UTF16.self))
        }
    }

    struct Hit {
        let chapter: Int
        let passage: Int
        let offset: Int
    }

    struct Snippet {
        let before: String
        let match: String
        let after: String
    }

    private let chapters: [[Passage]]

    @concurrent
    func search(_ query: String) async throws -> [Hit] {
        let pattern = Array(query.utf16)
        guard !pattern.isEmpty else { return [] }
        var prefix = Array(repeating: 0, count: pattern.count)
        var length = 0
        for i in 1..<pattern.count {
            while length > 0, pattern[length] != pattern[i] { length = prefix[length - 1] }
            if pattern[length] == pattern[i] { length += 1 }
            prefix[i] = length
        }

        var hits: [Hit] = []
        for (chapterIndex, chapter) in chapters.enumerated() {
            try Task.checkCancellation()
            for (passageIndex, passage) in chapter.enumerated() {
                var matched = 0
                for (i, unit) in passage.units.enumerated() {
                    while matched > 0, unit != pattern[matched] { matched = prefix[matched - 1] }
                    if unit == pattern[matched] {
                        matched += 1
                        if matched == pattern.count {
                            hits.append(Hit(chapter: chapterIndex, passage: passageIndex, offset: i + 1 - matched))
                            matched = 0
                        }
                    }
                }
            }
        }
        return hits
    }

    func start(of hit: Hit) -> Int {
        chapters[hit.chapter][hit.passage].start + hit.offset
    }

    func snippet(_ hit: Hit, length: Int) -> Snippet {
        let units = chapters[hit.chapter][hit.passage].units
        let end = hit.offset + length
        var from = max(0, hit.offset - 22)
        var to = min(end + 22, units.count)
        if from > 0, UTF16.isTrailSurrogate(units[from]) { from -= 1 }
        if to < units.count, UTF16.isTrailSurrogate(units[to]) { to += 1 }
        func context(_ range: Range<Int>) -> String {
            String(decoding: units[range], as: UTF16.self).replacing(/\s+/, with: " ")
        }
        return Snippet(before: context(from..<hit.offset),
                       match: String(decoding: units[hit.offset..<end], as: UTF16.self),
                       after: context(end..<to))
    }

    @concurrent
    static func prepare(id: String, data: Data, spine: [EpubManifestItem],
                        cacheRoot: URL = .cachesDirectory) async throws -> BookSearch {
        let directory = cacheRoot.appending(path: "Rede/BookSearch-v1", directoryHint: .isDirectory)
        let cache = directory.appendingPathComponent(id)
        let decoder = JSONDecoder()
        if let bytes = try? Data(contentsOf: cache, options: .mappedIfSafe),
           let chapters = try? decoder.decode([[Passage]].self, from: bytes), chapters.count == spine.count {
            return BookSearch(chapters: chapters)
        }

        let archive = try Archive(data: data, accessMode: .read)
        let entries = Dictionary(archive.lazy.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let extractor = try await SearchTextExtractor()
        var chapters: [[Passage]] = []
        var batch: [[String: String]] = []
        for (i, item) in spine.enumerated() {
            try Task.checkCancellation()
            let type = item.mediaType
            var source = ""
            if ["application/xhtml+xml", "text/html", "application/xml", "text/xml"].contains(type) {
                guard let entry = entries[item.path] else { throw EpubParsingError.entryNotFound(item.path) }
                var bytes = Data()
                _ = try archive.extract(entry) { bytes.append($0) }
                let utf16 = bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff])
                guard let text = String(data: bytes, encoding: utf16 ? .utf16 : .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                source = text
            }
            batch.append(["type": type, "source": source])
            if batch.count == 32 || i + 1 == spine.count {
                let json = try await extractor.extract(batch)
                chapters += try decoder.decode([[Passage]].self, from: Data(json.utf8))
                batch.removeAll(keepingCapacity: true)
            }
        }
        try Task.checkCancellation()
        let encoded = try JSONEncoder().encode(chapters)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded.write(to: cache, options: .atomic)
        return BookSearch(chapters: chapters)
    }
}

@MainActor
private final class SearchTextExtractor {
    private let webView = WKWebView()
    private let script: String

    init() throws {
        let offsets = try AppResourceSchemeHandler.data(named: "offsets.js")
        script = String(decoding: offsets, as: UTF8.self) + "\n" + """
        const parser = new DOMParser();
        const blocks = "p,div,li,h1,h2,h3,h4,h5,h6,td,th,blockquote,section,article,pre,figcaption";
        return JSON.stringify(batch.map(({type, source}) => {
          if (!source) return [];
          const chapter = parser.parseFromString(source, type);
          if (!chapter.body) throw new Error("Invalid EPUB chapter");
          const passages = [];
          const breaks = chapter.querySelectorAll("br,hr");
          let nextBreak = 0, owner, current;
          for (const unit of units(chapter)) {
            while (nextBreak < breaks.length &&
                   breaks[nextBreak].compareDocumentPosition(unit.node) & Node.DOCUMENT_POSITION_FOLLOWING) {
              current = null;
              nextBreak++;
            }
            const parent = unit.node.parentElement;
            if (!unit.text || parent.closest("script,style,template,[hidden]")) {
              current = null;
              continue;
            }
            const block = parent.closest(blocks);
            if (!current || block !== owner) {
              current = [unit.start, ""];
              passages.push(current);
              owner = block;
            }
            current[1] += unit.node.data;
          }
          return passages;
        }));
        """
    }

    func extract(_ batch: [[String: String]]) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, arguments: ["batch": batch],
                                                           contentWorld: .defaultClient)
        guard let json = result as? String else { throw CocoaError(.coderInvalidValue) }
        return json
    }
}
