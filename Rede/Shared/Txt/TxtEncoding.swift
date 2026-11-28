import Foundation
import CUchardet

nonisolated enum TxtConversionError: LocalizedError {
    case emptyContent
    case encodingFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .emptyContent: "文件内容为空"
        case .encodingFailed: "无法识别文本编码"
        case .conversionFailed: "TXT 转换失败"
        }
    }
}

nonisolated enum TxtEncoding {
    private static let sampleSize = 131_072

    static func decode(_ data: Data) throws -> String {
        guard !data.isEmpty else { throw TxtConversionError.emptyContent }

        if let bomDecoded = decodeWithBOM(data) {
            return bomDecoded
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let charset = detectCharset(data),
           let encoding = stringEncoding(for: charset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }

        for encoding in fallbackEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }

        throw TxtConversionError.encodingFailed
    }

    private static func decodeWithBOM(_ data: Data) -> String? {
        let bytes = data.prefix(4)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data.dropFirst(4), encoding: .utf32BigEndian)
        }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return String(data: data.dropFirst(4), encoding: .utf32LittleEndian)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        return nil
    }

    private static func detectCharset(_ data: Data) -> String? {
        guard let detector = uchardet_new() else { return nil }
        defer { uchardet_delete(detector) }

        let length = min(data.count, sampleSize)
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            _ = uchardet_handle_data(detector, base, length)
        }
        uchardet_data_end(detector)

        guard let cString = uchardet_get_charset(detector) else { return nil }
        let name = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func stringEncoding(for charset: String) -> String.Encoding? {
        switch charset.lowercased() {
        case "utf-8", "utf8", "ascii", "us-ascii":
            return .utf8
        case "gb18030", "gbk", "gb2312", "gb_2312-80", "hz-gb-2312":
            return cfEncoding(.GB_18030_2000)
        case "big5", "big5-hkscs", "big5-2003":
            return cfEncoding(.big5_HKSCS_1999)
        case "euc-tw":
            return cfEncoding(.EUC_TW)
        case "shift_jis", "shift-jis", "sjis", "cp932":
            return .shiftJIS
        case "euc-jp":
            return .japaneseEUC
        case "euc-kr", "cp949", "uhc":
            return cfEncoding(.EUC_KR)
        case "utf-16":
            return .utf16
        case "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        case "utf-32":
            return .utf32
        case "utf-32le":
            return .utf32LittleEndian
        case "utf-32be":
            return .utf32BigEndian
        case "windows-1252", "iso-8859-1":
            return .windowsCP1252
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            let raw = CFStringConvertEncodingToNSStringEncoding(cf)
            return String.Encoding(rawValue: raw)
        }
    }

    private static func cfEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
        return String.Encoding(rawValue: raw)
    }

    private static var fallbackEncodings: [String.Encoding] {
        [
            cfEncoding(.GB_18030_2000),
            cfEncoding(.big5_HKSCS_1999),
            .utf16,
            .shiftJIS,
            .windowsCP1252,
        ]
    }
}
