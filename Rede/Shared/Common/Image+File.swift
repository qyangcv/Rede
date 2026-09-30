import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension Image {
    init?(fileURL url: URL) {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        self.init(uiImage: image)
        #endif
    }

    init?(data: Data) {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}
