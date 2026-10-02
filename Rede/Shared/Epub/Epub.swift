import Foundation
import Kanna
import ZIPFoundation

nonisolated struct EpubModel {
    let opfPath: String
    let metadata: EpubMetadata
    let manifest: [String: EpubManifestItem]
    let spine: [EpubManifestItem]
    let toc: [EpubTocEntry]
    let cover: EpubManifestItem?
}

nonisolated struct EpubMetadata {
    let version: String?
    let title: String
    let author: String
    let language: String
    let publisher: String?
    let date: String?
    let isbn: String?
}

nonisolated struct EpubManifestItem {
    let id: String
    let path: String
    let mediaType: String
    let properties: Set<String>
}

nonisolated struct EpubTocEntry: Identifiable {
    let id: String
    let title: String
    let path: String
    let fragment: String?
    let children: [EpubTocEntry]
}

nonisolated struct EpubBook {
    let model: EpubModel
    let fetcher: EpubFetcher
}

nonisolated enum EpubParsingError: Error {
    case containerNotFound
    case opfNotFound
    case entryNotFound(String)
}

nonisolated func parseEpub(_ data: Data) throws -> EpubBook {
    let archive = try Archive(data: data, accessMode: .read)
    let fetcher = EpubFetcher(archive: archive)

    let containerXML = try XML(xml: fetcher.data(at: "META-INF/container.xml"), encoding: .utf8)
    guard let opfPath = containerXML
        .at_xpath("//*[local-name()='rootfile']/@full-path")?.text else {
        throw EpubParsingError.opfNotFound
    }

    let opfXML = try XML(xml: fetcher.data(at: opfPath), encoding: .utf8)

    let metadata = parseMetadata(opfXML)
    let manifest = parseManifest(opfXML, opfPath: opfPath)
    let spine = parseSpine(opfXML, manifest: manifest)
    let toc = parseToc(fetcher: fetcher, opfXML: opfXML, manifest: manifest)
    let cover = findCover(opfXML, manifest: manifest)

    let model = EpubModel(opfPath: opfPath, metadata: metadata,
                          manifest: manifest, spine: spine, toc: toc, cover: cover)
    return EpubBook(model: model, fetcher: fetcher)
}

nonisolated private func parseMetadata(_ opfXML: Searchable) -> EpubMetadata {
    func values(_ name: String) -> [String] {
        opfXML.xpath("//*[local-name()='metadata']/*[local-name()='\(name)']")
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    let version = opfXML.at_xpath("/*[local-name()='package']/@version")?.text
    return EpubMetadata(
        version: version,
        title: values("title").first ?? "",
        author: values("creator").joined(separator: "、"),
        language: values("language").first ?? "",
        publisher: values("publisher").first,
        date: values("date").first.map { String($0.prefix(10)) },
        isbn: values("identifier").lazy.compactMap(isbn(from:)).first)
}

nonisolated private func isbn(from identifier: String) -> String? {
    var raw = identifier
    if raw.lowercased().hasPrefix("urn:isbn:") { raw = String(raw.dropFirst(9)) }
    let compact = raw.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    return compact.wholeMatch(of: /\d{13}|\d{9}[\dXx]/) != nil ? compact : nil
}

nonisolated private func parseManifest(_ opfXML: Searchable, opfPath: String) -> [String: EpubManifestItem] {
    var manifest: [String: EpubManifestItem] = [:]

    for element in opfXML.xpath("//*[local-name()='manifest']/*[local-name()='item']") {
        guard let id = element["id"],
              let href = element["href"],
              let mediaType = element["media-type"] else { continue }
        let path = resolveHref(href, relativeTo: opfPath).path
        let properties = element["properties"]?
            .split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        manifest[id] = EpubManifestItem(id: id, path: path, mediaType: mediaType,
                                        properties: Set(properties))
    }
    return manifest
}

nonisolated private func parseSpine(_ opfXML: Searchable, manifest: [String: EpubManifestItem]) -> [EpubManifestItem] {
    opfXML.xpath("//*[local-name()='spine']/*[local-name()='itemref']")
        .compactMap { $0["idref"].flatMap { manifest[$0] } }
}

nonisolated private func parseToc(fetcher: EpubFetcher, opfXML: Searchable,
                      manifest: [String: EpubManifestItem]) -> [EpubTocEntry] {
    if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
       let toc = try? parseNavToc(fetcher: fetcher, navPath: nav.path), !toc.isEmpty {
        return toc
    }
    guard let ncxPath = findNcxPath(opfXML, manifest: manifest),
          let toc = try? parseNcxToc(fetcher: fetcher, ncxPath: ncxPath) else { return [] }
    return toc
}

nonisolated private func findNcxPath(_ opfXML: Searchable, manifest: [String: EpubManifestItem]) -> String? {
    guard let tocId = opfXML.at_xpath("//*[local-name()='spine']/@toc")?.text else { return nil }
    return manifest[tocId]?.path
}

nonisolated private func findCover(_ opfXML: Searchable, manifest: [String: EpubManifestItem]) -> EpubManifestItem? {
    if let item = manifest.values.first(where: { $0.properties.contains("cover-image") }) {
        return item
    }
    guard let coverId = opfXML.at_xpath("//*[local-name()='meta'][@name='cover']/@content")?.text
    else { return nil }
    return manifest[coverId]
}

nonisolated private func parseNcxToc(fetcher: EpubFetcher, ncxPath: String) throws -> [EpubTocEntry] {
    let ncxXML = try XML(xml: fetcher.data(at: ncxPath), encoding: .utf8)
    guard let navMap = ncxXML.at_xpath("//*[local-name()='navMap']") else { return [] }
    return parseNavPoints(navMap, ncxPath: ncxPath, idPrefix: "")
}

nonisolated private func parseNavPoints(_ parent: Searchable, ncxPath: String, idPrefix: String) -> [EpubTocEntry] {
    var toc: [EpubTocEntry] = []

    for (index, node) in parent.xpath("./*[local-name()='navPoint']").enumerated() {
        let id = idPrefix.isEmpty ? "\(index)" : "\(idPrefix).\(index)"

        let title = node.at_xpath("./*[local-name()='navLabel']/*[local-name()='text']")?.text ?? ""
        let src = node.at_xpath("./*[local-name()='content']/@src")?.text ?? ""
        let (path, fragment) = resolveHref(src, relativeTo: ncxPath)

        let children = parseNavPoints(node, ncxPath: ncxPath, idPrefix: id)
        toc.append(EpubTocEntry(id: id,
                              title: normalizeTitle(title),
                              path: path,
                              fragment: fragment,
                              children: children))
    }
    return toc
}

nonisolated private func parseNavToc(fetcher: EpubFetcher, navPath: String) throws -> [EpubTocEntry] {
    let navXML = try XML(xml: fetcher.data(at: navPath), encoding: .utf8)
    guard let list = navXML.at_xpath(
        "//*[local-name()='nav'][@*[local-name()='type']='toc']/*[local-name()='ol']")
    else { return [] }
    return parseNavList(list, navPath: navPath, idPrefix: "")
}

nonisolated private func parseNavList(_ list: Searchable, navPath: String, idPrefix: String) -> [EpubTocEntry] {
    var toc: [EpubTocEntry] = []

    for (index, li) in list.xpath("./*[local-name()='li']").enumerated() {
        let id = idPrefix.isEmpty ? "\(index)" : "\(idPrefix).\(index)"

        let label = li.at_xpath("./*[local-name()='a' or local-name()='span']")
        let title = label?.text ?? ""
        let href = label?["href"] ?? ""
        let (path, fragment) = resolveHref(href, relativeTo: navPath)

        let children = li.at_xpath("./*[local-name()='ol']")
            .map { parseNavList($0, navPath: navPath, idPrefix: id) } ?? []
        toc.append(EpubTocEntry(id: id,
                                title: normalizeTitle(title),
                                path: path,
                                fragment: fragment,
                                children: children))
    }
    return toc
}

nonisolated private func normalizeTitle(_ title: String) -> String {
    title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

nonisolated private func resolveHref(_ href: String, relativeTo documentPath: String) -> (path: String, fragment: String?) {
    let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let rawPath = parts.first.map(String.init) ?? ""
    let fragment = parts.count > 1 ? String(parts[1]) : nil

    if rawPath.isEmpty {
        return (documentPath, fragment)
    }

    let decoded = rawPath.removingPercentEncoding ?? rawPath
    let baseDir = (documentPath as NSString).deletingLastPathComponent
    let joined = baseDir.isEmpty ? decoded : baseDir + "/" + decoded
    return (normalizePath(joined), fragment)
}

nonisolated private func normalizePath(_ path: String) -> String {
    var components: [String] = []
    for component in path.split(separator: "/") {
        switch component {
        case ".":
            continue
        case "..":
            if !components.isEmpty { components.removeLast() }
        default:
            components.append(String(component))
        }
    }
    return components.joined(separator: "/")
}

nonisolated struct EpubFetcher {
    let archive: Archive

    func exist(at path: String) -> Bool {
        archive[path] != nil
    }

    func data(at path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw EpubParsingError.entryNotFound(path)
        }
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }
}

