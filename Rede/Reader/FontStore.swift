import Foundation
import CryptoKit
import os

@Observable
final class FontStore {
    static let shared = FontStore()
    private static let log = Logger(subsystem: "Rede", category: "FontStore")
    nonisolated private static let chunkSize = 1 << 18

    private(set) var downloaded: Set<ReaderFont>
    private(set) var received: [ReaderFont: Int] = [:]
    private(set) var failed: Set<ReaderFont> = []
    @ObservationIgnored private var tasks: [ReaderFont: Task<Void, Never>] = [:]

    private init() {
        downloaded = Set(ReaderFont.allCases.filter {
            $0.package != nil && FileManager.default.fileExists(atPath: $0.directory.path(percentEncoded: false))
        })
    }

    func download(_ font: ReaderFont) {
        guard let package = font.package, tasks[font] == nil, !downloaded.contains(font) else { return }
        failed.remove(font)
        received[font] = 0
        tasks[font] = Task {
            do {
                try await install(font, from: package)
                downloaded.insert(font)
            } catch where Task.isCancelled {
            } catch {
                Self.log.error("下载 \(font.rawValue) 失败：\(error)")
                failed.insert(font)
            }
            received[font] = nil
            tasks[font] = nil
        }
    }

    func cancel(_ font: ReaderFont) {
        tasks[font]?.cancel()
    }

    func delete(_ font: ReaderFont) {
        do {
            try FileManager.default.removeItem(at: font.directory)
        } catch {
            Self.log.error("删除 \(font.rawValue) 失败：\(error)")
            return
        }
        downloaded.remove(font)
        if Settings.shared.readerStyle.font == font {
            Settings.shared.readerStyle.font = .original
        }
    }

    private func install(_ font: ReaderFont, from package: FontPackage) async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for file in package.files.values {
            try await Self.fetch(package.release.appending(component: file.name),
                                 to: staging.appending(component: file.name),
                                 sha256: file.sha256) { bytes in
                self.received[font, default: 0] += bytes
            }
        }

        try? fm.removeItem(at: font.directory)
        try fm.createDirectory(at: AppPaths.fonts, withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: font.directory)
    }

    @concurrent nonisolated
    private static func fetch(_ url: URL, to destination: URL, sha256: String,
                              onProgress: @MainActor @escaping (Int) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var hasher = SHA256()
        var iterator = bytes.makeAsyncIterator()
        var buffer = Data(capacity: chunkSize)
        var finished = false
        while !finished {
            buffer.removeAll(keepingCapacity: true)
            while buffer.count < chunkSize, let byte = try await iterator.next() {
                buffer.append(byte)
            }
            finished = buffer.count < chunkSize
            try handle.write(contentsOf: buffer)
            hasher.update(data: buffer)
            await onProgress(buffer.count)
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw URLError(.cannotDecodeContentData) }
    }
}
