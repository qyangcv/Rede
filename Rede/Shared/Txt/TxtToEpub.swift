import Foundation
import ZIPFoundation

nonisolated enum TxtToEpub {
    private static let mimetypeData = Data("application/epub+zip".utf8)
    private static let containerXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)

    static func convert(_ data: Data, title: String) throws -> Data {
        let text = try TxtEncoding.decode(data)
        let book = try TxtSplitter.split(text, fallbackTitle: title)
        return try package(book)
    }

    private static func package(_ book: TxtBook) throws -> Data {
        let archive = try Archive(accessMode: .create)
        let bookID = "urn:uuid:\(UUID().uuidString.lowercased())"

        try addEntry(to: archive, path: "mimetype", data: mimetypeData, compression: .none)
        try addEntry(to: archive, path: "META-INF/container.xml", data: containerXML, compression: .deflate)
        try addEntry(to: archive, path: "OEBPS/content.opf", data: buildOPF(for: book, bookID: bookID), compression: .deflate)
        try addEntry(to: archive, path: "OEBPS/nav.xhtml", data: buildNav(for: book), compression: .deflate)
        try addEntry(to: archive, path: "OEBPS/toc.ncx", data: buildNCX(for: book, bookID: bookID), compression: .deflate)

        for (index, chapter) in book.chapters.enumerated() {
            let path = "OEBPS/chapter_\(index).xhtml"
            let xhtml = buildChapterXHTML(chapter, language: book.language)
            try addEntry(to: archive, path: path, data: xhtml, compression: .deflate)
        }

        guard let epubData = archive.data else {
            throw TxtConversionError.conversionFailed
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

    private static func buildOPF(for book: TxtBook, bookID: String) -> Data {
        var manifestItems = [
            "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
            "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>",
        ]
        var spineItems: [String] = []

        for index in book.chapters.indices {
            let id = "chapter_\(index)"
            manifestItems.append("    <item id=\"\(id)\" href=\"\(id).xhtml\" media-type=\"application/xhtml+xml\"/>")
            spineItems.append("    <itemref idref=\"\(id)\"/>")
        }

        var metaLines = [
            "    <dc:identifier id=\"BookId\">\(escapeXML(bookID))</dc:identifier>",
            "    <dc:title>\(escapeXML(book.title))</dc:title>",
            "    <dc:language>\(escapeXML(book.language))</dc:language>",
        ]
        if !book.author.isEmpty {
            metaLines.append("    <dc:creator>\(escapeXML(book.author))</dc:creator>")
        }

        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookId">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            \(metaLines.joined(separator: "\n"))
              </metadata>
              <manifest>
            \(manifestItems.joined(separator: "\n"))
              </manifest>
              <spine toc="ncx">
            \(spineItems.joined(separator: "\n"))
              </spine>
            </package>
            """
        return Data(xml.utf8)
    }

    private static func buildNav(for book: TxtBook) -> Data {
        let items = book.chapters.enumerated().map { index, chapter in
            "        <li><a href=\"chapter_\(index).xhtml\">\(escapeXML(chapter.title))</a></li>"
        }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escapeXML(book.language))">
            <head>
              <meta charset="UTF-8"/>
              <title>\(escapeXML(book.title))</title>
            </head>
            <body>
              <nav epub:type="toc" id="toc">
                <h1>目录</h1>
                <ol>
            \(items.joined(separator: "\n"))
                </ol>
              </nav>
            </body>
            </html>
            """
        return Data(xml.utf8)
    }

    private static func buildNCX(for book: TxtBook, bookID: String) -> Data {
        let navPoints = book.chapters.enumerated().map { index, chapter in
            """
                <navPoint id="navPoint-\(index + 1)" playOrder="\(index + 1)">
                  <navLabel><text>\(escapeXML(chapter.title))</text></navLabel>
                  <content src="chapter_\(index).xhtml"/>
                </navPoint>
            """
        }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <head>
                <meta name="dtb:uid" content="\(escapeXML(bookID))"/>
                <meta name="dtb:depth" content="1"/>
                <meta name="dtb:totalPageCount" content="0"/>
                <meta name="dtb:maxPageNumber" content="0"/>
              </head>
              <docTitle><text>\(escapeXML(book.title))</text></docTitle>
              <navMap>
            \(navPoints.joined(separator: "\n"))
              </navMap>
            </ncx>
            """
        return Data(xml.utf8)
    }

    private static func buildChapterXHTML(_ chapter: TxtChapter, language: String) -> Data {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE html>",
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"\(escapeXML(language))\">",
            "<head>",
            "  <meta charset=\"UTF-8\"/>",
            "  <title>\(escapeXML(chapter.title))</title>",
            "</head>",
            "<body>",
            "  <h1>\(escapeXML(chapter.title))</h1>",
        ]
        lines.reserveCapacity(lines.count + chapter.paragraphs.count + 2)
        for paragraph in chapter.paragraphs {
            lines.append("  <p>\(escapeXML(paragraph))</p>")
        }
        lines.append("</body>")
        lines.append("</html>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
