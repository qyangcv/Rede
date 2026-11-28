import Foundation
import CLibMobi

nonisolated enum MobiConversionError: LocalizedError {
    case invalidFile
    case encrypted
    case unsupportedReplica
    case emptyContent
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile: "书籍文件损坏"
        case .encrypted: "无法打开加密书籍"
        case .unsupportedReplica: "不支持固定版式书籍"
        case .emptyContent: "书籍内容为空"
        case .conversionFailed: "书籍格式转换失败"
        }
    }
}

nonisolated struct MobiPartEntry {
    let path: String
    let mediaType: String
    let data: Data
}

nonisolated struct MobiExtractedMetadata {
    let title: String
    let author: String
    let language: String
    let publisher: String?
    let date: String?
    let isbn: String?
}

nonisolated struct MobiExtractedBook {
    let metadata: MobiExtractedMetadata
    let opf: Data?
    let markup: [MobiPartEntry]
    let flow: [MobiPartEntry]
    let resources: [MobiPartEntry]
}

nonisolated enum MobiExtractor {
    static func extract(_ data: Data) throws -> MobiExtractedBook {
        guard !data.isEmpty else { throw MobiConversionError.invalidFile }

        guard let mobi = mobi_init() else { throw MobiConversionError.conversionFailed }
        defer { mobi_free(mobi) }

        let loadResult: MOBI_RET = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return MOBI_DATA_CORRUPT }
            guard let file = fmemopen(UnsafeMutableRawPointer(mutating: baseAddress), rawBuffer.count, "rb") else {
                return MOBI_INIT_FAILED
            }
            defer { fclose(file) }
            return mobi_load_file(mobi, file)
        }

        guard loadResult == MOBI_SUCCESS else { throw MobiConversionError.invalidFile }
        if mobi_is_encrypted(mobi) { throw MobiConversionError.encrypted }
        if mobi_is_replica(mobi) { throw MobiConversionError.unsupportedReplica }

        let metadata = readMetadata(from: mobi)

        guard let rawml = mobi_init_rawml(mobi) else { throw MobiConversionError.conversionFailed }
        defer { mobi_free_rawml(rawml) }

        guard mobi_parse_rawml(rawml, mobi) == MOBI_SUCCESS else {
            throw MobiConversionError.conversionFailed
        }

        let markup = collectParts(rawml.pointee.markup, prefix: "part")
        let flow = collectParts(rawml.pointee.flow?.pointee.next, prefix: "flow")
        let (opf, resources) = collectResources(rawml.pointee.resources)

        guard !markup.isEmpty else { throw MobiConversionError.emptyContent }

        return MobiExtractedBook(
            metadata: metadata,
            opf: opf,
            markup: markup,
            flow: flow,
            resources: resources
        )
    }

    private static func readMetadata(from mobi: UnsafePointer<MOBIData>) -> MobiExtractedMetadata {
        func readString(_ getter: (UnsafePointer<MOBIData>?) -> UnsafeMutablePointer<CChar>?) -> String? {
            guard let ptr = getter(mobi) else { return nil }
            defer { free(ptr) }
            let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return MobiExtractedMetadata(
            title: readString(mobi_meta_get_title) ?? "",
            author: readString(mobi_meta_get_author) ?? "",
            language: readString(mobi_meta_get_language) ?? "zh",
            publisher: readString(mobi_meta_get_publisher),
            date: readString(mobi_meta_get_publishdate),
            isbn: readString(mobi_meta_get_isbn)
        )
    }

    private static func collectParts(_ head: UnsafeMutablePointer<MOBIPart>?, prefix: String) -> [MobiPartEntry] {
        var entries: [MobiPartEntry] = []
        var current = head
        while let part = current {
            let value = part.pointee
            if value.size > 0, let bytes = value.data {
                let meta = mobi_get_filemeta_by_type(value.type)
                let ext = cTupleString(meta.extension)
                let mime = cTupleString(meta.mime_type)
                let filename = String(format: "OEBPS/%@%05lu.%@", prefix, UInt(value.uid), ext)
                entries.append(MobiPartEntry(
                    path: filename,
                    mediaType: mime.isEmpty ? "application/octet-stream" : mime,
                    data: Data(bytes: bytes, count: value.size)
                ))
            }
            current = value.next
        }
        return entries
    }

    private static func collectResources(_ head: UnsafeMutablePointer<MOBIPart>?) -> (Data?, [MobiPartEntry]) {
        var opf: Data?
        var entries: [MobiPartEntry] = []
        var current = head
        while let part = current {
            let value = part.pointee
            if value.size > 0, let bytes = value.data {
                let meta = mobi_get_filemeta_by_type(value.type)
                let data = Data(bytes: bytes, count: value.size)
                if meta.type == T_OPF {
                    opf = data
                } else {
                    let ext = cTupleString(meta.extension)
                    let mime = cTupleString(meta.mime_type)
                    let filename = String(format: "OEBPS/resource%05lu.%@", UInt(value.uid), ext)
                    entries.append(MobiPartEntry(
                        path: filename,
                        mediaType: mime.isEmpty ? "application/octet-stream" : mime,
                        data: data
                    ))
                }
            }
            current = value.next
        }
        return (opf, entries)
    }

    private static func cTupleString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { buffer in
            let bytes = buffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
