import Foundation

nonisolated struct TxtChapter: Sendable {
    let title: String
    let paragraphs: [String]
}

nonisolated struct TxtBook: Sendable {
    let title: String
    let author: String
    let language: String
    let chapters: [TxtChapter]
}

nonisolated enum TxtSplitter {
    private static let sampleLength = 512_000
    private static let maxLengthWithNoToc = 10_240
    private static let maxLengthWithToc = 102_400
    private static let overRuleCount = 2
    private static let trimCharacterSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}\u{FEFF}"))

    static func split(_ rawText: String, fallbackTitle: String) throws -> TxtBook {
        let normalized = sanitize(rawText)
        guard !normalized.trimmingCharacters(in: trimCharacterSet).isEmpty else {
            throw TxtConversionError.emptyContent
        }

        let (title, author) = extractMetadata(from: normalized, fallbackTitle: fallbackTitle)
        let language = detectLanguage(normalized)
        let chapters: [TxtChapter]

        if let rule = selectTocRule(in: normalized), let regex = rule.regex() {
            chapters = splitWithRule(normalized, regex: regex)
        } else {
            chapters = splitWithoutRule(normalized, fallbackTitle: title)
        }

        guard !chapters.isEmpty else {
            throw TxtConversionError.emptyContent
        }

        return TxtBook(title: title, author: author, language: language, chapters: chapters)
    }

    private static func sanitize(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(unified.unicodeScalars.count)
        for scalar in unified.unicodeScalars {
            let v = scalar.value
            if v == 0x09 || v == 0x0A || (v >= 0x20 && v != 0x7F && v != 0xFFFE && v != 0xFFFF) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func selectTocRule(in text: String) -> TxtTocRule? {
        let nsText = text as NSString
        let scanLength = min(nsText.length, sampleLength)
        let sampleRange = NSRange(location: 0, length: scanLength)

        var maxNum = -1
        var selected: TxtTocRule?

        for rule in TxtTocRule.enabled {
            guard let regex = rule.regex() else { continue }
            var start = 0
            var csNum = 0
            var numE = 0

            regex.enumerateMatches(in: text, options: [], range: sampleRange) { match, _, _ in
                guard let match else { return }
                let range = match.range
                let contentLength = range.location - start
                if start == 0 || contentLength > 1000 {
                    let title = nsText.substring(with: range).trimmingCharacters(in: trimCharacterSet)
                    if !title.isEmpty {
                        csNum += 1
                    }
                    start = NSMaxRange(range)
                } else if contentLength < 100 {
                    numE += 1
                }
            }

            if csNum >= numE * 3 && csNum > maxNum + overRuleCount {
                maxNum = csNum
                selected = rule
                if maxNum > 70 {
                    break
                }
            }
        }

        return selected
    }

    private static func splitWithRule(_ text: String, regex: NSRegularExpression) -> [TxtChapter] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else {
            return splitWithoutRule(text, fallbackTitle: "正文")
        }

        var chapters: [TxtChapter] = []
        let firstLocation = matches[0].range.location
        if firstLocation > 0 {
            let preface = nsText.substring(with: NSRange(location: 0, length: firstLocation))
            let paragraphs = extractParagraphs(from: preface)
            if !paragraphs.isEmpty {
                chapters.append(contentsOf: splitLongChapter(title: "前言", rawBody: preface))
            }
        }

        for index in matches.indices {
            let match = matches[index]
            let title = nsText.substring(with: match.range).trimmingCharacters(in: trimCharacterSet)
            guard !title.isEmpty else { continue }

            let bodyStart = NSMaxRange(match.range)
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            let bodyLength = max(0, bodyEnd - bodyStart)
            let body = bodyLength > 0 ? nsText.substring(with: NSRange(location: bodyStart, length: bodyLength)) : ""

            if bodyLength > maxLengthWithToc {
                chapters.append(contentsOf: splitLongChapter(title: title, rawBody: body))
            } else {
                let paragraphs = extractParagraphs(from: body)
                chapters.append(TxtChapter(title: title, paragraphs: paragraphs))
            }
        }

        return chapters
    }

    private static func splitLongChapter(title: String, rawBody: String) -> [TxtChapter] {
        let chunks = chunkText(rawBody, maxLength: maxLengthWithNoToc)
        if chunks.count <= 1 {
            return [TxtChapter(title: title, paragraphs: extractParagraphs(from: rawBody))]
        }
        return chunks.enumerated().map { index, chunk in
            TxtChapter(title: "\(title)(\(index + 1))", paragraphs: extractParagraphs(from: chunk))
        }
    }

    private static func splitWithoutRule(_ text: String, fallbackTitle: String) -> [TxtChapter] {
        let chunks = chunkText(text, maxLength: maxLengthWithNoToc)
        if chunks.count <= 1 {
            let paragraphs = extractParagraphs(from: text)
            guard !paragraphs.isEmpty else { return [] }
            let chapterTitle = fallbackTitle.isEmpty ? "正文" : fallbackTitle
            return [TxtChapter(title: chapterTitle, paragraphs: paragraphs)]
        }

        var chapters: [TxtChapter] = []
        for (index, chunk) in chunks.enumerated() {
            let paragraphs = extractParagraphs(from: chunk)
            guard !paragraphs.isEmpty else { continue }
            chapters.append(TxtChapter(title: "第\(index + 1)章", paragraphs: paragraphs))
        }
        return chapters
    }

    private static func chunkText(_ text: String, maxLength: Int) -> [String] {
        let nsText = text as NSString
        let total = nsText.length
        guard total > maxLength else { return [text] }

        var chunks: [String] = []
        var offset = 0
        while offset < total {
            let remaining = total - offset
            if remaining <= maxLength {
                let tail = nsText.substring(with: NSRange(location: offset, length: remaining))
                if remaining <= 100, let last = chunks.popLast() {
                    chunks.append(last + tail)
                } else {
                    chunks.append(tail)
                }
                break
            }

            let searchStart = offset + maxLength
            let searchLimit = min(total, searchStart + 2048)
            let newlineRange = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: searchStart, length: searchLimit - searchStart)
            )
            let end = newlineRange.location != NSNotFound ? NSMaxRange(newlineRange) : searchStart
            chunks.append(nsText.substring(with: NSRange(location: offset, length: end - offset)))
            offset = end
        }
        return chunks
    }

    private static func extractParagraphs(from text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: trimCharacterSet) }
            .filter { !$0.isEmpty }
    }

    private static func extractMetadata(from text: String, fallbackTitle: String) -> (title: String, author: String) {
        var title = fallbackTitle.trimmingCharacters(in: trimCharacterSet)
        var author = ""

        if let match = title.firstMatch(of: /^《([^》]+)》\s*(?:作者[：:\s]*)?(.*)$/) {
            let extractedTitle = String(match.1).trimmingCharacters(in: trimCharacterSet)
            let extractedAuthor = String(match.2).trimmingCharacters(in: trimCharacterSet)
            if !extractedTitle.isEmpty { title = extractedTitle }
            if !extractedAuthor.isEmpty { author = extractedAuthor }
        } else if let match = title.firstMatch(of: /^(.+?)\s+[-—–]\s+(.+)$/) {
            let left = String(match.1).trimmingCharacters(in: trimCharacterSet)
            let right = String(match.2).trimmingCharacters(in: trimCharacterSet)
            if !left.isEmpty && !right.isEmpty {
                title = left
                author = right
            }
        }

        if author.isEmpty {
            let headLines = text.prefix(2000)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .prefix(20)
            for line in headLines {
                let trimmed = line.trimmingCharacters(in: trimCharacterSet)
                if let match = trimmed.firstMatch(of: /^(?:作者|著|Author)[：:]\s*(.{1,40})$/) {
                    let candidate = String(match.1).trimmingCharacters(in: trimCharacterSet)
                    if !candidate.isEmpty {
                        author = candidate
                        break
                    }
                }
            }
        }

        if title.isEmpty {
            title = "未命名"
        }

        return (title, author)
    }

    private static func detectLanguage(_ text: String) -> String {
        for scalar in text.unicodeScalars.prefix(4000) {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                return "zh"
            }
        }
        return "en"
    }
}
