import SwiftUI

struct ReaderScreen: View {
    // 左右两侧各占宽度的 30%，点击翻页；中间点击显示工具栏
    private static let edge = 0.3

    @Environment(ReaderSession.self) private var session
    @State private var chromeVisible = false

    var body: some View {
        NavigationStack {
            if let reader = session.reader {
                // 铺满全屏，工具栏浮在上面：显示或隐藏工具栏不能改变 WebView 尺寸，否则会触发 reflow
                ReaderView(reader: reader, page: session.page, chapter: session.chapter)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭", systemImage: "xmark") { session.close() }
                        }
                    }
                    .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
                    .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                    .statusBarHidden(!chromeVisible)
                    .navigationTitle(session.chapter?.entry.title ?? session.book?.name ?? "")
                    .navigationBarTitleDisplayMode(.inline)
                    .onAppear {
                        reader.onGesture = { handle($0, reader: reader) }
                    }
                    .id(ObjectIdentifier(reader))
            }
        }
    }

    private func handle(_ gesture: ReaderGesture, reader: Reader) {
        switch gesture {
        case .tap(let x):
            if chromeVisible { chromeVisible = false }
            else if x < Self.edge { reader.prev() }
            else if x > 1 - Self.edge { reader.next() }
            else { chromeVisible = true }
        case .swipe(.left): reader.next()
        case .swipe(.right): reader.prev()
        }
    }
}
