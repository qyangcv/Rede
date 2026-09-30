import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        allowsLinkPreview = false
        // 翻页由 reader.js 滚动章节 iframe 完成，外层 scrollView 不滚动，也不按安全区域加 inset
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")
    }
}

struct ReaderWebViewContainer: UIViewRepresentable {
    let reader: Reader

    func makeUIView(context: Context) -> ReaderWebView {
        reader.webView
    }

    func updateUIView(_ uiView: ReaderWebView, context: Context) {}
}

extension Reader {
    // iOS 上翻页靠触摸，不需要键盘焦点
    func focus() {}
}

// 相邻页渲染器的 WebView 垫在主 WebView 下面：同尺寸、同安全区，排版一致，又被主 WebView 的背景挡住
struct PageRendererHost: View {
    let pages: PageRenderer

    var body: some View {
        ZStack {
            ForEach(PageDirection.allCases, id: \.self) { direction in
                if let reader = pages.readers[direction] {
                    ReaderWebViewContainer(reader: reader)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
