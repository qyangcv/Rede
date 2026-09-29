import SwiftUI
import SwiftData

@main
struct RedeApp: App {
    @State private var session = ReaderSession()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                // 启动时还没有窗口，外观要等场景出现后再应用
                .onAppear { Settings.shared.appearance.apply() }
        }
        .modelContainer(.localLibrary)
        .environment(session)
    }
}
