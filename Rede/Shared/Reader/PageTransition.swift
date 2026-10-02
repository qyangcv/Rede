import SwiftUI

enum PageDirection: CaseIterable {
    case prev, next
    var step: Int { self == .next ? 1 : -1 }
}

enum PageTransition: String, CaseIterable, Identifiable, Codable {
    case none
    #if os(iOS)
    case curl
    #endif

    #if os(iOS)
    static let `default` = Self.curl
    #else
    static let `default` = Self.none
    #endif

    var id: Self { self }

    var name: String {
        switch self {
        case .none: "无动画"
        #if os(iOS)
        case .curl: "仿真"
        #endif
        }
    }
}

protocol PageTurner: AnyObject {
    var pages: PageRenderer? { get }
    var layer: AnyView { get }
    func turn(_ direction: PageDirection)
    func detach()
}
