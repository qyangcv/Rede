import SwiftUI
import SwiftData

@main
struct RedeApp: App {
    @State private var session = ReaderSession()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SyncMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .onAppear { Settings.shared.appearance.apply() }
        }
        .modelContainer(.library)
        .environment(session)
        .onChange(of: scenePhase) { _, phase in
            // 进入后台时 ReaderSession 会保存阅读进度，这里向系统要时间把它传上去
            if phase == .background { BackgroundUpload.shared.begin() }
        }
    }
}
