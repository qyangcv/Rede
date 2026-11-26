import Foundation
import Kanna
import Observation
import ZIPFoundation

enum ChapterPreviewContent: Equatable, Sendable {
    case text([String])
    case illustration
    case empty
}

@MainActor
@Observable
final class ChapterPreviewStore {
    private var cache: [Int: ChapterPreviewContent] = [:]
    private var activeChapter: Int?
    private var activeTask: Task<Void, Never>?
    private let extractor: ChapterPreviewExtractor?

    init(epubData: Data?, spinePaths: [String], maxLines: Int) {
        if let epubData {
            self.extractor = ChapterPreviewExtractor(data: epubData, spinePaths: spinePaths, maxLines: maxLines)
        } else {
            self.extractor = nil
        }
    }

    func cached(chapter: Int) -> ChapterPreviewContent? {
        cache[chapter]
    }

    func load(chapter: Int, title: String?) {
        if cache[chapter] != nil {
            cancelAll()
            return
        }
        guard activeChapter != chapter, let extractor else { return }
        activeTask?.cancel()
        activeChapter = chapter
        activeTask = Task { [weak self] in
            let content = await extractor.extract(chapter: chapter, title: title)
            guard let self, !Task.isCancelled else { return }
            if let content {
                self.cache[chapter] = content
            }
            if self.activeChapter == chapter {
                self.activeChapter = nil
                self.activeTask = nil
            }
        }
    }

    func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        activeChapter = nil
    }
}

private actor ChapterPreviewExtractor {
    private let data: Data
    private let spinePaths: [String]
    private let maxLines: Int
    private var archive: Archive?
    private var entries: [String: Entry] = [:]
    private var loadedArchive = false
    private var cache: [Int: ChapterPreviewContent] = [:]
    private var cacheOrder: [Int] = []
    private let maxCached = 128

    init(data: Data, spinePaths: [String], maxLines: Int) {
        self.data = data
        self.spinePaths = spinePaths
        self.maxLines = max(maxLines, 1)
    }

    func extract(chapter: Int, title: String?) -> ChapterPreviewContent? {
        if let cached = cache[chapter] {
            return cached
        }
        if Task.isCancelled { return nil }
        guard spinePaths.indices.contains(chapter) else { return .empty }
        prepareArchive()
        if Task.isCancelled { return nil }
        let path = spinePaths[chapter]
        guard let archive, let entry = entries[path] else { return .empty }
        var bytes = Data()
        do {
            _ = try archive.extract(entry) { bytes.append($0) }
        } catch {
            return .empty
        }
        if Task.isCancelled { return nil }
        let result = Self.parsePreview(from: bytes, chapterTitle: title, maxLines: maxLines)
        store(result, for: chapter)
        return result
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

    private func store(_ content: ChapterPreviewContent, for chapter: Int) {
        cache[chapter] = content
        cacheOrder.append(chapter)
        if cacheOrder.count > maxCached {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
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

    private static func parsePreview(from data: Data, chapterTitle: String?, maxLines: Int) -> ChapterPreviewContent {
        let utf16 = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
        let encoding: String.Encoding = utf16 ? .utf16 : .utf8
        let doc: (any Searchable)? = (try? XML(xml: data, encoding: encoding))
            ?? (try? HTML(html: data, encoding: encoding))
        guard let doc else { return .empty }

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
