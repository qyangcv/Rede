import SwiftUI

struct ReaderWindow: View {
    @Environment(ReaderSession.self) private var session

    var body: some View {
        ZStack {
            if let reader = session.reader {
                ReaderView(reader: reader, page: session.page, chapter: session.chapter)
                    .overlay(alignment: .top) {
                        Color.clear
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .gesture(WindowDragGesture())
                            .allowsWindowActivationEvents(true)
                    }
                    .id(ObjectIdentifier(reader))
            } else {
                ContentUnavailableView("No book opened", systemImage: "book")
            }
        }
        .ignoresSafeArea()
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(session.chapter?.path.map(\.title).joined(separator: " › ") ?? session.book?.name ?? "Reader Window")
        .onDisappear { session.close() }
    }
}
