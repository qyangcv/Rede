import SwiftUI
import os

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
           switch self {
           case .system: "circle.lefthalf.filled"
           case .light: "sun.max"
           case .dark: "moon"
           }
       }
}

struct LibrarySorting: Equatable {
    let key: LibrarySort
    var order: SortOrder

    init(key: LibrarySort, order: SortOrder? = nil) {
        self.key = key
        self.order = order ?? key.defaultOrder
    }
}

@Observable
final class Settings {
    static let shared = Settings()
    private static let log = Logger(subsystem: "Rede", category: "Settings")

    var readerStyle: ReaderStyle { didSet { save() } }

    var appearance: Appearance {
        didSet {
            appearance.apply()
            save()
        }
    }

    var pageTransition: PageTransition { didSet { save() } }

    #if os(macOS)
    var readerTitle: ReaderTitle { didSet { save() } }
    #endif

    #if os(iOS)
    var brightness: Double { didSet { save() } }

    var showsStatus: Bool { didSet { save() } }
    #endif

    var libraryLayout: LibraryLayout { didSet { save() } }

    var librarySorting: LibrarySorting {
        didSet { if librarySorting != oldValue { save() } }
    }

    var iCloudSync: Bool { didSet { save() } }

    #if DEBUG
    private static let defaultICloudSync = true
    #else
    private static let defaultICloudSync = false
    #endif

    private struct Snapshot: Codable {
        var readerStyle: ReaderStyle?
        var appearance: Appearance?
        var pageTransition: PageTransition?
        #if os(macOS)
        var readerTitle: ReaderTitle?
        #endif
        #if os(iOS)
        var brightness: Double?
        var showsStatus: Bool?
        #endif
        var libraryLayout: LibraryLayout?
        var librarySort: LibrarySort?
        var libraryOrder: SortOrder?
        var iCloudSync: Bool?
    }

    private init() {
        let snapshot = (try? Data(contentsOf: AppPaths.settings))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        readerStyle = snapshot?.readerStyle ?? .default
        appearance = snapshot?.appearance ?? .system
        pageTransition = snapshot?.pageTransition ?? .default
        #if os(macOS)
        readerTitle = snapshot?.readerTitle ?? .chapter
        #endif
        #if os(iOS)
        brightness = snapshot?.brightness ?? 1
        showsStatus = snapshot?.showsStatus ?? true
        #endif
        libraryLayout = snapshot?.libraryLayout ?? .grid
        librarySorting = LibrarySorting(key: snapshot?.librarySort ?? .imported, order: snapshot?.libraryOrder)
        iCloudSync = snapshot?.iCloudSync ?? Self.defaultICloudSync
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.settings.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var snapshot = Snapshot(readerStyle: readerStyle, appearance: appearance,
                                    pageTransition: pageTransition,
                                    libraryLayout: libraryLayout, librarySort: librarySorting.key,
                                    libraryOrder: librarySorting.order,
                                    iCloudSync: iCloudSync)
            #if os(macOS)
            snapshot.readerTitle = readerTitle
            #endif
            #if os(iOS)
            snapshot.brightness = brightness
            snapshot.showsStatus = showsStatus
            #endif
            try encoder.encode(snapshot)
                .write(to: AppPaths.settings, options: .atomic)
        } catch {
            Self.log.error("保存设置失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
