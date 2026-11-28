import Foundation
import Kanna
import ZIPFoundation

nonisolated enum MobiToEpub {
    private static let mimetypeData = Data("application/epub+zip".utf8)
    private static let containerXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)

    static func convert(_ data: Data) throws -> Data {
        let extracted = try MobiExtractor.extract(data)
        return try package(MobiSplitter.splitIfNeeded(extracted))
    }

    private static func package(_ book: MobiExtractedBook) throws -> Data {
        let archive = try Archive(accessMode: .create)

        try addEntry(to: archive, path: "mimetype", data: mimetypeData, compression: .none)
        try addEntry(to: archive, path: "META-INF/container.xml", data: containerXML, compression: .deflate)

        let opfData = normalizedOPF(for: book)
        try addEntry(to: archive, path: "OEBPS/content.opf", data: opfData, compression: .deflate)

        for entry in book.markup {
            let xhtml = normalizeXHTML(entry.data)
            try addEntry(to: archive, path: entry.path, data: xhtml, compression: .deflate)
        }

        for entry in book.flow {
            try addEntry(to: archive, path: entry.path, data: entry.data, compression: .deflate)
        }

        for entry in book.resources {
            try addEntry(to: archive, path: entry.path, data: entry.data, compression: .deflate)
        }

        guard let epubData = archive.data else {
            throw MobiConversionError.conversionFailed
        }
        return epubData
    }

    private static func addEntry(to archive: Archive, path: String, data: Data,
                                 compression: CompressionMethod) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: compression) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<(start + size))
        }
    }

    private static func normalizeXHTML(_ data: Data) -> Data {
        if isValidXHTML(data) {
            return data
        }
        guard let doc = try? HTML(html: data, encoding: .utf8),
              let xml = doc.toXML else {
            return data
        }
        let xhtml = ensureXHTMLNamespace(in: xml)
        guard let normalized = xhtml.data(using: .utf8),
              isValidXHTML(normalized) else {
            return data
        }
        return normalized
    }

    private static func isValidXHTML(_ data: Data) -> Bool {
        guard let xml = try? XML(xml: data, encoding: .utf8) else { return false }
        let hasXHTMLRoot = xml.at_xpath(
            "/*[local-name()='html' and namespace-uri()='http://www.w3.org/1999/xhtml']"
        ) != nil
        let hasBody = xml.at_xpath("//*[local-name()='body']") != nil
        return hasXHTMLRoot && hasBody
    }

    private static func ensureXHTMLNamespace(in xml: String) -> String {
        guard let match = xml.firstMatch(of: /<html\b([^>]*)>/) else { return xml }
        if match.1.contains("xmlns=") { return xml }
        let replacement = "<html xmlns=\"http://www.w3.org/1999/xhtml\"\(match.1)>"
        return xml.replacingCharacters(in: match.range, with: replacement)
    }

    private static func normalizedOPF(for book: MobiExtractedBook) -> Data {
        if let opf = book.opf, (try? XML(xml: opf, encoding: .utf8)) != nil {
            return opf
        }
        return buildFallbackOPF(for: book)
    }

    private static func buildFallbackOPF(for book: MobiExtractedBook) -> Data {
        let meta = book.metadata
        var manifestItems: [String] = []
        var spineItems: [String] = []

        for (index, entry) in book.markup.enumerated() {
            let id = "part\(index)"
            let href = relativeHref(entry.path)
            manifestItems.append("    <item id=\"\(id)\" href=\"\(escapeXML(href))\" media-type=\"application/xhtml+xml\"/>")
            spineItems.append("    <itemref idref=\"\(id)\"/>")
        }

        for (index, entry) in book.flow.enumerated() {
            let id = "flow\(index)"
            let href = relativeHref(entry.path)
            manifestItems.append("    <item id=\"\(id)\" href=\"\(escapeXML(href))\" media-type=\"\(escapeXML(entry.mediaType))\"/>")
        }

        var tocID: String?
        for (index, entry) in book.resources.enumerated() {
            let id = "res\(index)"
            let href = relativeHref(entry.path)
            if entry.mediaType == "application/x-dtbncx+xml" || href.hasSuffix(".ncx") {
                tocID = id
            }
            manifestItems.append("    <item id=\"\(id)\" href=\"\(escapeXML(href))\" media-type=\"\(escapeXML(entry.mediaType))\"/>")
        }

        var metaLines = [
            "    <dc:title>\(escapeXML(meta.title))</dc:title>",
            "    <dc:creator>\(escapeXML(meta.author))</dc:creator>",
            "    <dc:language>\(escapeXML(meta.language))</dc:language>",
        ]
        if let publisher = meta.publisher {
            metaLines.append("    <dc:publisher>\(escapeXML(publisher))</dc:publisher>")
        }
        if let date = meta.date {
            metaLines.append("    <dc:date>\(escapeXML(date))</dc:date>")
        }
        if let isbn = meta.isbn {
            metaLines.append("    <dc:identifier>\(escapeXML(isbn))</dc:identifier>")
        }

        let spineAttr = tocID.map { " toc=\"\($0)\"" } ?? ""
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
            \(metaLines.joined(separator: "\n"))
              </metadata>
              <manifest>
            \(manifestItems.joined(separator: "\n"))
              </manifest>
              <spine\(spineAttr)>
            \(spineItems.joined(separator: "\n"))
              </spine>
            </package>
            """
        return Data(xml.utf8)
    }

    private static func relativeHref(_ path: String) -> String {
        path.hasPrefix("OEBPS/") ? String(path.dropFirst(6)) : path
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
