import Foundation
import Kanna
import Observation
import ZIPFoundation

nonisolated struct ChapterPreviewKey: Hashable, Sendable {
    let chapter: Int
    let offset: Int?
}

nonisolated enum ChapterPreviewContent: Equatable, Sendable {
    case text([String])
    case illustration
    case empty
}

@MainActor
@Observable
final class ChapterPreviewStore {
    private var cache: [ChapterPreviewKey: ChapterPreviewContent] = [:]
    private var cacheOrder: [ChapterPreviewKey] = []
    private let maxCached = 128
    private var activeKey: ChapterPreviewKey?
    private var activeTask: Task<Void, Never>?
    private let extractor: ChapterPreviewExtractor?

    init(epubData: Data?, spinePaths: [String], maxLines: Int) {
        if let epubData {
            self.extractor = ChapterPreviewExtractor(data: epubData, spinePaths: spinePaths, maxLines: maxLines)
        } else {
            self.extractor = nil
        }
    }

    func cached(key: ChapterPreviewKey) -> ChapterPreviewContent? {
        cache[key]
    }

    func load(chapter: Int, title: String?) {
        let key = ChapterPreviewKey(chapter: chapter, offset: nil)
        startLoad(key: key) { extractor in
            await extractor.extractChapter(chapter: chapter, title: title)
        }
    }

    func load(chapter: Int, offset: Int, fallbackText: String) {
        let key = ChapterPreviewKey(chapter: chapter, offset: offset)
        startLoad(key: key) { extractor in
            await extractor.extractOffset(chapter: chapter, offset: offset, fallbackText: fallbackText)
        }
    }

    func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        activeKey = nil
    }

    private func startLoad(key: ChapterPreviewKey,
                           operation: @escaping @Sendable (ChapterPreviewExtractor) async -> ChapterPreviewContent?) {
        if cache[key] != nil {
            cancelAll()
            return
        }
        guard activeKey != key, let extractor else { return }
        activeTask?.cancel()
        activeKey = key
        activeTask = Task { [weak self] in
            let content = await operation(extractor)
            guard let self, !Task.isCancelled else { return }
            if let content {
                self.store(content, for: key)
            }
            if self.activeKey == key {
                self.activeKey = nil
                self.activeTask = nil
            }
        }
    }

    private func store(_ content: ChapterPreviewContent, for key: ChapterPreviewKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = content
        if cacheOrder.count > maxCached {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

private actor ChapterPreviewExtractor {
    private let data: Data
    private let spinePaths: [String]
    private let maxLines: Int
    private var archive: Archive?
    private var entries: [String: Entry] = [:]
    private var loadedArchive = false

    init(data: Data, spinePaths: [String], maxLines: Int) {
        self.data = data
        self.spinePaths = spinePaths
        self.maxLines = max(maxLines, 1)
    }

    func extractChapter(chapter: Int, title: String?) -> ChapterPreviewContent? {
        guard let bytes = readChapterData(chapter) else { return Task.isCancelled ? nil : .empty }
        if Task.isCancelled { return nil }
        return Self.parseChapterStart(from: bytes, chapterTitle: title, maxLines: maxLines)
    }

    func extractOffset(chapter: Int, offset: Int, fallbackText: String) -> ChapterPreviewContent? {
        guard let bytes = readChapterData(chapter) else {
            if Task.isCancelled { return nil }
            return fallbackText.isEmpty ? .empty : .text([fallbackText])
        }
        if Task.isCancelled { return nil }
        return Self.parseFromOffset(from: bytes, offset: max(offset, 0),
                                    fallbackText: fallbackText, maxLines: maxLines)
    }

    private func readChapterData(_ chapter: Int) -> Data? {
        if Task.isCancelled { return nil }
        guard spinePaths.indices.contains(chapter) else { return nil }
        prepareArchive()
        if Task.isCancelled { return nil }
        let path = spinePaths[chapter]
        guard let archive, let entry = entries[path] else { return nil }
        var bytes = Data()
        do {
            _ = try archive.extract(entry) { bytes.append($0) }
        } catch {
            return nil
        }
        return bytes
    }

    private func prepareArchive() {
        guard !loadedArchive else { return }
        loadedArchive = true
        let opened: Archive
        do {
            opened = try Archive(data: data, accessMode: .read)
        } catch {
            return
        }
        self.archive = opened
        var map: [String: Entry] = [:]
        for entry in opened where map[entry.path] == nil {
            map[entry.path] = entry
        }
        self.entries = map
    }

    private static let excludedAncestors = [
        "script", "style", "svg", "h1", "h2", "h3", "h4", "h5", "h6",
    ].map { "local-name()='\($0)'" }.joined(separator: " or ")

    private static let blockNames = [
        "p", "div", "blockquote", "li", "dd", "pre",
    ].map { "local-name()='\($0)'" }.joined(separator: " or ")

    private static let mediaNames = [
        "img", "svg", "video",
    ].map { "local-name()='\($0)'" }.joined(separator: " or ")

    private static let mediaTags: Set<String> = ["img", "svg", "video"]
    private static let skippedTags: Set<String> = ["script", "style"]
    private static let breakTags: Set<String> = ["br", "hr"]
    private static let blockTags: Set<String> = [
        "p", "div", "blockquote", "li", "dd", "dt", "pre",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "section", "article", "tr", "figcaption",
    ]

    private static func parseDocument(from data: Data) -> (any Searchable)? {
        let utf16 = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
        let encoding: String.Encoding = utf16 ? .utf16 : .utf8
        return (try? XML(xml: data, encoding: encoding))
            ?? (try? HTML(html: data, encoding: encoding))
    }

    private static func parseChapterStart(from data: Data, chapterTitle: String?, maxLines: Int) -> ChapterPreviewContent {
        guard let doc = parseDocument(from: data) else { return .empty }

        let body = "//*[local-name()='body']"
        let blockXPath = "\(body)//*[(\(blockNames)) and not(.//*[\(blockNames)]) and not(ancestor-or-self::*[\(excludedAncestors)])]"
        let normalizedTitle = chapterTitle.map(normalizeForMatch)

        var paragraphs: [String] = []
        var totalChars = 0
        let maxParagraphs = max(maxLines, 1)
        let maxChars = max(maxParagraphs * 40, 120)

        for node in doc.xpath(blockXPath) {
            guard let raw = node.text else { continue }
            let cleaned = normalizeText(raw)
            guard !cleaned.isEmpty else { continue }
            if paragraphs.isEmpty, let normalizedTitle, !normalizedTitle.isEmpty,
               isDuplicateTitle(cleaned, normalizedTitle: normalizedTitle) {
                continue
            }
            paragraphs.append(cleaned)
            totalChars += cleaned.count
            if paragraphs.count >= maxParagraphs || totalChars >= maxChars {
                break
            }
        }

        if paragraphs.isEmpty {
            let textXPath = "\(body)//text()[not(ancestor::*[\(excludedAncestors)])]"
            var buffer = ""
            for node in doc.xpath(textXPath) {
                guard let raw = node.text else { continue }
                let cleaned = normalizeText(raw)
                guard !cleaned.isEmpty else { continue }
                if buffer.isEmpty, let normalizedTitle, !normalizedTitle.isEmpty,
                   isDuplicateTitle(cleaned, normalizedTitle: normalizedTitle) {
                    continue
                }
                if !buffer.isEmpty { buffer += " " }
                buffer += cleaned
                if buffer.count >= maxChars { break }
            }
            if !buffer.isEmpty {
                paragraphs.append(String(buffer.prefix(maxChars)))
            }
        }

        if !paragraphs.isEmpty {
            return .text(paragraphs)
        }

        let mediaCount = doc.xpath("\(body)//*[\(mediaNames)]").count
        return mediaCount > 0 ? .illustration : .empty
    }

    private static func parseFromOffset(from data: Data, offset: Int,
                                        fallbackText: String, maxLines: Int) -> ChapterPreviewContent {
        guard let doc = parseDocument(from: data),
              let body = doc.at_xpath("//*[local-name()='body']") else {
            return fallbackText.isEmpty ? .empty : .text([fallbackText])
        }

        let maxParagraphs = max(maxLines, 1)
        let maxChars = max(maxParagraphs * 40, 120)
        var cursor = 0
        var paragraphs: [String] = []
        var current = ""
        var totalChars = 0
        var sawMediaAtOffset = false
        var done = false

        func flush() {
            let cleaned = normalizeText(current)
            current = ""
            guard !cleaned.isEmpty else { return }
            paragraphs.append(cleaned)
            totalChars += cleaned.count
            if paragraphs.count >= maxParagraphs || totalChars >= maxChars {
                done = true
            }
        }

        func walk(_ node: Kanna.XMLElement) {
            for child in node.xpath("./node()") {
                if done { return }
                let tag = (child.tagName ?? "").lowercased()
                if mediaTags.contains(tag) {
                    if cursor >= offset, paragraphs.isEmpty, current.isEmpty {
                        sawMediaAtOffset = true
                    }
                    cursor += 1
                    continue
                }
                if skippedTags.contains(tag) {
                    cursor += child.text?.utf16.count ?? 0
                    continue
                }
                if breakTags.contains(tag) {
                    if cursor >= offset { flush() }
                    continue
                }
                if tag == "text" || tag == "cdata-section" {
                    let raw = child.text ?? ""
                    let units = Array(raw.utf16)
                    let length = units.count
                    if cursor + length <= offset {
                        cursor += length
                        continue
                    }
                    let sliceStart = max(offset - cursor, 0)
                    cursor += length
                    let piece = sliceStart == 0 ? raw : String(decoding: units[sliceStart...], as: UTF16.self)
                    current += piece
                    if totalChars + current.count >= maxChars + 40 {
                        flush()
                    }
                    continue
                }
                if blockTags.contains(tag) {
                    if cursor >= offset { flush() }
                    walk(child)
                    if cursor >= offset { flush() }
                } else {
                    walk(child)
                }
            }
        }

        walk(body)
        if !done { flush() }

        if !paragraphs.isEmpty {
            return .text(paragraphs)
        }
        if sawMediaAtOffset {
            return .illustration
        }
        if !fallbackText.isEmpty {
            return .text([fallbackText])
        }
        let mediaCount = doc.xpath("//*[local-name()='body']//*[\(mediaNames)]").count
        return mediaCount > 0 ? .illustration : .empty
    }

    private static func normalizeText(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeForMatch(_ text: String) -> String {
        text.unicodeScalars
            .filter { !$0.properties.isWhitespace && !CharacterSet.punctuationCharacters.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func isDuplicateTitle(_ candidate: String, normalizedTitle: String) -> Bool {
        let normalizedCandidate = normalizeForMatch(candidate)
        guard !normalizedCandidate.isEmpty else { return false }
        return normalizedCandidate == normalizedTitle
            || normalizedTitle.hasSuffix(normalizedCandidate)
            || normalizedCandidate.hasSuffix(normalizedTitle) && normalizedCandidate.count <= normalizedTitle.count + 8
    }
}
