import SwiftUI
import SwiftData

@main
struct RedeApp: App {
    @State private var session = ReaderSession()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .onAppear { Settings.shared.appearance.apply() }
        }
        .modelContainer(.localLibrary)
        .environment(session)
    }
}
