import SwiftUI
import WebKit

final class ReaderWebView: WKWebView {
    var onBuildMenu: ((UIMenuBuilder) -> Void)?
    private let menuPresenter = MenuPresenter()

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        allowsLinkPreview = false
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addInteraction(menuPresenter.interaction)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented")
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        onBuildMenu?(builder)
    }

    func presentMenu(_ menu: UIMenu, at rect: CGRect) {
        menuPresenter.present(menu, at: rect)
    }
}

private final class MenuPresenter: NSObject, UIEditMenuInteractionDelegate {
    lazy var interaction = UIEditMenuInteraction(delegate: self)
    private var menu: UIMenu?
    private var rect = CGRect.null

    func present(_ menu: UIMenu, at rect: CGRect) {
        self.menu = menu
        self.rect = rect
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil,
                                                                  sourcePoint: CGPoint(x: rect.midX, y: rect.midY)))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        menu
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        rect
    }
}

struct ReaderWebViewContainer: UIViewRepresentable {
    let reader: Reader

    func makeUIView(context: Context) -> ReaderWebView {
        reader.webView.onBuildMenu = { [weak reader] builder in reader?.extendMenu(builder) }
        return reader.webView
    }

    func updateUIView(_ uiView: ReaderWebView, context: Context) {}
}

extension Reader {
    func focus() {}

    fileprivate func extendMenu(_ builder: UIMenuBuilder) {
        guard builder.system == .context, let onAnnotationAction else { return }
        let highlight = UIAction(title: "高亮", image: UIImage(systemName: "highlighter")) { _ in
            onAnnotationAction(.highlightSelection)
        }
        let note = UIAction(title: "笔记", image: UIImage(systemName: "square.and.pencil")) { _ in
            onAnnotationAction(.noteSelection)
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [highlight, note]), atStartOfMenu: .root)
    }
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
