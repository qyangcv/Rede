import Foundation
import Kanna

nonisolated enum MobiSplitter {
    private static let maxChunkBytes = 40_000
    private static let minMergedChunkBytes = 16_000
    private static let maxUnmergedChunks = 200

    private struct NodePiece {
        let xml: String
        let byteCount: Int
        let anchors: [String]
        let isPagebreak: Bool
        let hasContent: Bool
    }

    static func splitIfNeeded(_ book: MobiExtractedBook) -> MobiExtractedBook {
        guard book.markup.count == 1,
              let single = book.markup.first,
              let doc = try? HTML(html: single.data, encoding: .utf8),
              let body = doc.at_xpath("//body") else {
            return book
        }

        let headXML = doc.at_xpath("//head")?.toXML ?? "<head/>"
        let sourceHref = relativeHref(single.path)
        let ncxAnchors = collectNCXAnchors(from: book.resources, sourceHref: sourceHref)
        let pieces = collectPieces(from: body)
        guard !pieces.isEmpty else { return book }

        let chunks = splitPieces(pieces, ncxAnchors: ncxAnchors)
        guard chunks.count > 1 else { return book }

        let fileNames = chunks.indices.map { String(format: "part%05d.html", $0) }
        var anchorToFile: [String: String] = [:]
        for (index, chunk) in chunks.enumerated() {
            let fileName = fileNames[index]
            for piece in chunk {
                for anchor in piece.anchors where anchorToFile[anchor] == nil {
                    anchorToFile[anchor] = fileName
                }
            }
        }

        var newMarkup: [MobiPartEntry] = []
        for (index, chunk) in chunks.enumerated() {
            let fileName = fileNames[index]
            let rawBody = chunk.map(\.xml).joined()
            let rewrittenBody = rewriteLinks(in: rawBody, sourceHref: sourceHref,
                                             currentFile: fileName, anchorToFile: anchorToFile)
            let xhtml = """
                <?xml version="1.0" encoding="utf-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml">
                \(headXML)
                <body>\(rewrittenBody)</body>
                </html>
                """
            newMarkup.append(MobiPartEntry(
                path: "OEBPS/\(fileName)",
                mediaType: "application/xhtml+xml",
                data: Data(xhtml.utf8)
            ))
        }

        let newResources = book.resources.map { entry -> MobiPartEntry in
            guard entry.mediaType == "application/x-dtbncx+xml" || entry.path.hasSuffix(".ncx"),
                  let text = String(data: entry.data, encoding: .utf8) else {
                return entry
            }
            let rewritten = rewriteAttrTargets(in: text, attribute: "src",
                                               sourceHref: sourceHref, anchorToFile: anchorToFile)
            return MobiPartEntry(path: entry.path, mediaType: entry.mediaType, data: Data(rewritten.utf8))
        }

        let newOPF = book.opf.flatMap {
            rewriteOPF($0, sourceHref: sourceHref, newFiles: fileNames, anchorToFile: anchorToFile)
        }

        return MobiExtractedBook(
            metadata: book.metadata,
            opf: newOPF,
            markup: newMarkup,
            flow: book.flow,
            resources: newResources
        )
    }

    private static let atomicTags: Set<String> = ["table", "svg", "pre", "code", "math", "video", "audio"]

    private static func collectPieces(from container: Kanna.XMLElement) -> [NodePiece] {
        var result: [NodePiece] = []
        for node in container.xpath("./node()") {
            guard let xml = node.toXML, !xml.isEmpty else { continue }
            let tag = node.tagName?.lowercased()
            if tag != "text",
               let tag,
               !atomicTags.contains(tag),
               xml.utf8.count > maxChunkBytes || node.at_xpath(".//pagebreak") != nil {
                let children = Array(node.xpath("./node()"))
                if !children.isEmpty {
                    result.append(contentsOf: collectPieces(from: node))
                    continue
                }
            }
            if let piece = makePiece(from: node, xml: xml) {
                result.append(piece)
            }
        }
        return result
    }

    private static func makePiece(from node: Kanna.XMLElement, xml: String) -> NodePiece? {
        let tag = node.tagName?.lowercased()
        let isPagebreak = tag == "pagebreak"
        let hasContent: Bool
        if isPagebreak {
            hasContent = false
        } else if tag == "text" {
            hasContent = !(node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        } else {
            let hasText = !(node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasMedia = node.at_xpath("self::img|self::svg|self::video|.//img|.//svg|.//video") != nil
            hasContent = hasText || hasMedia
        }

        var anchors: [String] = []
        if tag != "text" {
            if let id = node["id"], !id.isEmpty { anchors.append(id) }
            if tag == "a", let name = node["name"], !name.isEmpty { anchors.append(name) }
            for el in node.xpath(".//*[@id]") {
                if let id = el["id"], !id.isEmpty { anchors.append(id) }
            }
            for el in node.xpath(".//a[@name]") {
                if let name = el["name"], !name.isEmpty { anchors.append(name) }
            }
        }

        return NodePiece(
            xml: xml,
            byteCount: xml.utf8.count,
            anchors: anchors,
            isPagebreak: isPagebreak,
            hasContent: hasContent
        )
    }

    private static func splitPieces(_ pieces: [NodePiece], ncxAnchors: Set<String>) -> [[NodePiece]] {
        let byPagebreak = splitByPagebreak(pieces)
        var result: [[NodePiece]] = []
        for chunk in byPagebreak {
            let totalBytes = chunk.reduce(0) { $0 + $1.byteCount }
            if totalBytes <= maxChunkBytes {
                result.append(chunk)
                continue
            }
            let byNCX = splitByNCX(chunk, ncxAnchors: ncxAnchors)
            for sub in byNCX {
                let subBytes = sub.reduce(0) { $0 + $1.byteCount }
                if subBytes <= maxChunkBytes {
                    result.append(sub)
                } else {
                    result.append(contentsOf: splitBySize(sub))
                }
            }
        }
        let nonEmpty = result.filter { !$0.isEmpty }
        return nonEmpty.count > maxUnmergedChunks ? mergeTinyChunks(nonEmpty) : nonEmpty
    }

    private static func mergeTinyChunks(_ chunks: [[NodePiece]]) -> [[NodePiece]] {
        var merged: [[NodePiece]] = []
        var current: [NodePiece] = []
        var currentBytes = 0

        for chunk in chunks {
            let bytes = chunk.reduce(0) { $0 + $1.byteCount }
            if !current.isEmpty && currentBytes + bytes > maxChunkBytes {
                merged.append(current)
                current = []
                currentBytes = 0
            }
            current.append(contentsOf: chunk)
            currentBytes += bytes
            if currentBytes >= minMergedChunkBytes {
                merged.append(current)
                current = []
                currentBytes = 0
            }
        }
        if !current.isEmpty { merged.append(current) }
        return merged
    }

    private static func splitByPagebreak(_ pieces: [NodePiece]) -> [[NodePiece]] {
        var chunks: [[NodePiece]] = []
        var current: [NodePiece] = []
        var currentHasContent = false

        for piece in pieces {
            if piece.isPagebreak {
                if currentHasContent {
                    chunks.append(current)
                    current = []
                    currentHasContent = false
                }
                continue
            }
            current.append(piece)
            if piece.hasContent { currentHasContent = true }
        }
        if !current.isEmpty {
            if currentHasContent || chunks.isEmpty {
                chunks.append(current)
            } else {
                chunks[chunks.count - 1].append(contentsOf: current)
            }
        }
        return chunks
    }

    private static func splitByNCX(_ pieces: [NodePiece], ncxAnchors: Set<String>) -> [[NodePiece]] {
        guard !ncxAnchors.isEmpty else { return [pieces] }
        var chunks: [[NodePiece]] = []
        var current: [NodePiece] = []
        var currentHasContent = false

        for piece in pieces {
            let startsChapter = piece.anchors.contains { ncxAnchors.contains($0) }
            if startsChapter && currentHasContent {
                chunks.append(current)
                current = []
                currentHasContent = false
            }
            current.append(piece)
            if piece.hasContent { currentHasContent = true }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func splitBySize(_ pieces: [NodePiece]) -> [[NodePiece]] {
        var chunks: [[NodePiece]] = []
        var current: [NodePiece] = []
        var currentBytes = 0
        var currentHasContent = false

        for piece in pieces {
            if currentHasContent && currentBytes >= maxChunkBytes {
                chunks.append(current)
                current = []
                currentBytes = 0
                currentHasContent = false
            }
            current.append(piece)
            currentBytes += piece.byteCount
            if piece.hasContent { currentHasContent = true }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func collectNCXAnchors(from resources: [MobiPartEntry], sourceHref: String) -> Set<String> {
        var anchors: Set<String> = []
        for entry in resources where entry.mediaType == "application/x-dtbncx+xml" || entry.path.hasSuffix(".ncx") {
            guard let xml = try? XML(xml: entry.data, encoding: .utf8) else { continue }
            for node in xml.xpath("//*[local-name()='content']/@src") {
                guard let src = node.text else { continue }
                let parts = src.split(separator: "#", maxSplits: 1)
                if parts.count == 2, String(parts[0]) == sourceHref || parts[0].isEmpty {
                    anchors.insert(String(parts[1]))
                }
            }
        }
        return anchors
    }

    private static func rewriteLinks(in html: String, sourceHref: String, currentFile: String,
                                     anchorToFile: [String: String]) -> String {
        let escapedSource = NSRegularExpression.escapedPattern(for: sourceHref)
        guard let regex = try? NSRegularExpression(pattern: #"href="((?:"# + escapedSource + #")?#([^"]+))""#) else {
            return html
        }
        let ns = html as NSString
        var result = html
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let anchor = ns.substring(with: match.range(at: 2))
            guard let targetFile = anchorToFile[anchor] else { continue }
            let replacement = targetFile == currentFile
                ? "href=\"#\(anchor)\""
                : "href=\"\(targetFile)#\(anchor)\""
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func rewriteAttrTargets(in xml: String, attribute: String, sourceHref: String,
                                           anchorToFile: [String: String]) -> String {
        let escapedSource = NSRegularExpression.escapedPattern(for: sourceHref)
        guard let regex = try? NSRegularExpression(
            pattern: attribute + #"=""# + escapedSource + #"#([^"]+)""#
        ) else {
            return xml
        }
        let ns = xml as NSString
        var result = xml
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).reversed() {
            let anchor = ns.substring(with: match.range(at: 1))
            guard let targetFile = anchorToFile[anchor] else { continue }
            let replacement = "\(attribute)=\"\(targetFile)#\(anchor)\""
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func rewriteOPF(_ opfData: Data, sourceHref: String, newFiles: [String],
                                   anchorToFile: [String: String]) -> Data? {
        guard var opf = String(data: opfData, encoding: .utf8),
              let xml = try? XML(xml: opfData, encoding: .utf8),
              let originalItem = xml.at_xpath(
                  "//*[local-name()='manifest']/*[local-name()='item'][@href='\(sourceHref)']"
              ),
              let originalID = originalItem["id"] else {
            return nil
        }

        let escapedHref = NSRegularExpression.escapedPattern(for: sourceHref)
        guard let itemRegex = try? NSRegularExpression(
            pattern: #"<item\b[^>]*href=""# + escapedHref + #""[^>]*/>"#
        ),
        let itemrefRegex = try? NSRegularExpression(
            pattern: #"<itemref\b[^>]*idref=""# + NSRegularExpression.escapedPattern(for: originalID) + #""[^>]*/>"#
        ) else {
            return nil
        }

        let newIDs = newFiles.indices.map { $0 == 0 ? originalID : "\(originalID)_\($0)" }
        let manifestReplacement = zip(newIDs, newFiles).map { id, file in
            "<item id=\"\(id)\" href=\"\(file)\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n    ")
        let spineReplacement = newIDs.map { id in
            "<itemref idref=\"\(id)\"/>"
        }.joined(separator: "\n    ")

        let nsOPF = opf as NSString
        guard let itemMatch = itemRegex.firstMatch(in: opf, range: NSRange(location: 0, length: nsOPF.length)),
              let itemRange = Range(itemMatch.range, in: opf) else {
            return nil
        }
        opf.replaceSubrange(itemRange, with: manifestReplacement)

        let nsOPF2 = opf as NSString
        guard let refMatch = itemrefRegex.firstMatch(in: opf, range: NSRange(location: 0, length: nsOPF2.length)),
              let refRange = Range(refMatch.range, in: opf) else {
            return nil
        }
        opf.replaceSubrange(refRange, with: spineReplacement)

        opf = rewriteAttrTargets(in: opf, attribute: "href", sourceHref: sourceHref, anchorToFile: anchorToFile)

        guard let updated = opf.data(using: .utf8),
              (try? XML(xml: updated, encoding: .utf8)) != nil else {
            return nil
        }
        return updated
    }

    private static func relativeHref(_ path: String) -> String {
        path.hasPrefix("OEBPS/") ? String(path.dropFirst(6)) : path
    }
}
