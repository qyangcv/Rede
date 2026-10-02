import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        allowsLinkPreview = false
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
    func focus() {}
}

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
