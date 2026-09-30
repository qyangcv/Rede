import SwiftUI

enum PageDirection: CaseIterable {
    case prev, next
    var step: Int { self == .next ? 1 : -1 }
}

// 翻页方式。各平台只列出已实现的方式：allCases 就是可选项，switch 在每个平台上都是完备的。
// 新增一种方式：加 case 和 name，写一个 PageTurner，再在各平台的 makeTurner(reader:) 里各加一行
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

// 一种翻页方式的实现：接收翻页指令，在主 WebView 上装自己的手势，提供叠在 WebView 上的动画层
protocol PageTurner: AnyObject {
    // 相邻页截图；不需要截图的方式为 nil
    var pages: PageRenderer? { get }
    // 动画层，不接收触摸；没有动画的方式为 EmptyView
    var layer: AnyView { get }
    func turn(_ direction: PageDirection)
    // 换成别的翻页方式前调用：撤掉装在主 WebView 上的手势
    func detach()
}
