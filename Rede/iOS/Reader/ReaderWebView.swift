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
