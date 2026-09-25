// Parser Layer for epub2 & epub3

import Foundation
import ZIPFoundation

struct EpubModel {
    let opfPath: String
    let metadata: EpubMetadata
    let manifest: [String: EpubManifestItem]
    let spine: [EpubManifestItem]
    let toc: [EpubTocEntry]
    let cover: EpubManifestItem?
}

struct EpubMetadata {
    let title: String
    let author: String
    let language: String
}

struct EpubManifestItem {
    let id: String
    let path: String
    let mediaType: String
    let properties: Set<String>
}

struct EpubTocEntry: Identifiable {
    let id: String
    let title: String
    let path: String
    let fragment: String?
    let children: [EpubTocEntry]
}

struct EpubBook {
    let model: EpubModel
    let fetcher: EpubFetcher
}

enum EpubParsingError: Error {
    case containerNotFound
    case opfNotFound
    case entryNotFound(String)
}

func parseEpub(at fileURL: URL) throws -> EpubBook {
    let archive = try Archive(url: fileURL, accessMode: .read)
    let fetcher = EpubFetcher(archive: archive)

    let containerData = try fetcher.data(at: "META-INF/container.xml")
    let containerXML = try XMLDocument(data: containerData)
    guard let opfPath = try containerXML
        .nodes(forXPath: "//*[local-name()='rootfile']/@full-path")
        .first?.stringValue else {
        throw EpubParsingError.opfNotFound
    }

    let opfData = try fetcher.data(at: opfPath)
    let opfXML = try XMLDocument(data: opfData)

    let metadata = try parseMetadata(opfXML)
    let manifest = try parseManifest(opfXML, opfPath: opfPath)
    let spine = try parseSpine(opfXML, manifest: manifest)
    let toc = parseToc(fetcher: fetcher, opfXML: opfXML, manifest: manifest)
    let cover = findCover(opfXML, manifest: manifest)

    let model = EpubModel(opfPath: opfPath, metadata: metadata,
                          manifest: manifest, spine: spine, toc: toc, cover: cover)
    return EpubBook(model: model, fetcher: fetcher)
}

private func parseMetadata(_ opfXML: XMLDocument) throws -> EpubMetadata {
    let title = try opfXML.nodes(forXPath: "//*[local-name()='title']").first?.stringValue ?? ""
    let author = try opfXML.nodes(forXPath: "//*[local-name()='creator']").first?.stringValue ?? ""
    let language = try opfXML.nodes(forXPath: "//*[local-name()='language']").first?.stringValue ?? ""
    return EpubMetadata(title: title, author: author,
                        language: language.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func parseManifest(_ opfXML: XMLDocument, opfPath: String) throws -> [String: EpubManifestItem] {
    var manifest: [String: EpubManifestItem] = [:]

    let items = try opfXML.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
    for case let element as XMLElement in items {
        guard let id = element.attribute(forName: "id")?.stringValue,
              let href = element.attribute(forName: "href")?.stringValue,
              let mediaType = element.attribute(forName: "media-type")?.stringValue else { continue }
        let path = resolveHref(href, relativeTo: opfPath).path
        let properties = element.attribute(forName: "properties")?.stringValue?
            .split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        manifest[id] = EpubManifestItem(id: id, path: path, mediaType: mediaType,
                                        properties: Set(properties))
    }
    return manifest
}

private func parseSpine(_ opfXML: XMLDocument, manifest: [String: EpubManifestItem]) throws -> [EpubManifestItem] {
    var spine: [EpubManifestItem] = []

    let itemrefs = try opfXML.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
    for node in itemrefs {
        guard let element = node as? XMLElement,
              let idref = element.attribute(forName: "idref")?.stringValue,
              let item  = manifest[idref] else {continue}
        spine.append(item)
    }
    return spine
}

private func parseToc(fetcher: EpubFetcher, opfXML: XMLDocument,
                      manifest: [String: EpubManifestItem]) -> [EpubTocEntry] {
    if let nav = manifest.values.first(where: { $0.properties.contains("nav") }),
       let toc = try? parseNavToc(fetcher: fetcher, navPath: nav.path), !toc.isEmpty {
        return toc
    }
    guard let ncxPath = findNcxPath(opfXML, manifest: manifest),
          let toc = try? parseNcxToc(fetcher: fetcher, ncxPath: ncxPath) else { return [] }
    return toc
}

private func findNcxPath(_ opfXML: XMLDocument, manifest: [String: EpubManifestItem]) -> String? {
    guard let tocId = try? opfXML
        .nodes(forXPath: "//*[local-name()='spine']/@toc")
        .first?.stringValue else { return nil }
    return manifest[tocId]?.path
}


private func findCover(_ opfXML: XMLDocument, manifest: [String: EpubManifestItem]) -> EpubManifestItem? {
    if let item = manifest.values.first(where: { $0.properties.contains("cover-image") }) {
        return item
    }
    guard let coverId = try? opfXML
        .nodes(forXPath: "//*[local-name()='meta'][@name='cover']/@content")
        .first?.stringValue else { return nil }
    return manifest[coverId]
}

private func parseNcxToc(fetcher: EpubFetcher, ncxPath: String) throws -> [EpubTocEntry] {
    let ncxXML = try XMLDocument(data: fetcher.data(at: ncxPath))
    guard let navMap = try ncxXML.nodes(forXPath: "//*[local-name()='navMap']").first else { return [] }
    return try parseNavPoints(navMap, ncxPath: ncxPath, idPrefix: "")
}

private func parseNavPoints(_ parent: XMLNode, ncxPath: String, idPrefix: String) throws -> [EpubTocEntry] {
    var toc: [EpubTocEntry] = []

    let navPoints = try parent.nodes(forXPath: "./*[local-name()='navPoint']")
    for (index, node) in navPoints.enumerated() {
        let id = idPrefix.isEmpty ? "\(index)" : "\(idPrefix).\(index)"

        let title = try node.nodes(forXPath: "./*[local-name()='navLabel']/*[local-name()='text']")
            .first?.stringValue ?? ""
        let src = try node.nodes(forXPath: "./*[local-name()='content']/@src").first?.stringValue ?? ""
        let (path, fragment) = resolveHref(src, relativeTo: ncxPath)

        let children = try parseNavPoints(node, ncxPath: ncxPath, idPrefix: id)
        toc.append(EpubTocEntry(id: id,
                              title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                              path: path,
                              fragment: fragment,
                              children: children))
    }
    return toc
}

private func parseNavToc(fetcher: EpubFetcher, navPath: String) throws -> [EpubTocEntry] {
    let navXML = try XMLDocument(data: fetcher.data(at: navPath))
    guard let list = try navXML.nodes(forXPath:
        "//*[local-name()='nav'][@*[local-name()='type']='toc']/*[local-name()='ol']").first
    else { return [] }
    return try parseNavList(list, navPath: navPath, idPrefix: "")
}

private func parseNavList(_ list: XMLNode, navPath: String, idPrefix: String) throws -> [EpubTocEntry] {
    var toc: [EpubTocEntry] = []

    let items = try list.nodes(forXPath: "./*[local-name()='li']")
    for (index, li) in items.enumerated() {
        let id = idPrefix.isEmpty ? "\(index)" : "\(idPrefix).\(index)"

        // <li> 下是 <a href>（可跳转）或 <span>（仅分组标题），可选跟一个子 <ol>
        let label = try li.nodes(forXPath: "./*[local-name()='a' or local-name()='span']").first
        let title = label?.stringValue ?? ""
        let href = try label?.nodes(forXPath: "@href").first?.stringValue ?? ""
        let (path, fragment) = resolveHref(href, relativeTo: navPath)

        let children = try li.nodes(forXPath: "./*[local-name()='ol']").first
            .map { try parseNavList($0, navPath: navPath, idPrefix: id) } ?? []
        toc.append(EpubTocEntry(id: id,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                path: path,
                                fragment: fragment,
                                children: children))
    }
    return toc
}

private func resolveHref(_ href: String, relativeTo documentPath: String) -> (path: String, fragment: String?) {
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

private func normalizePath(_ path: String) -> String {
    // remove first `/`
    // remove `.`
    // resolve `..`
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

struct EpubFetcher {
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
 
