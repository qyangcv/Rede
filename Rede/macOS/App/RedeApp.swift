import SwiftUI
import SwiftData
import Sparkle

@main
struct RedeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private var session: ReaderSession { appDelegate.session }
    private let updaterController: SPUStandardUpdaterController = {
           #if DEBUG
           let startingUpdater = false
           #else
           let startingUpdater = true
           #endif
           return SPUStandardUpdaterController(
               startingUpdater: startingUpdater, updaterDelegate: nil, userDriverDelegate: nil)
       }()
    
    init () {
        Settings.shared.appearance.apply()
        SyncMonitor.shared.start()
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
    }
    
    var body: some Scene {
        Window("书库", id: "library") {
            ContentView()
        }
        .defaultSize(width: 600, height: 400)
        .modelContainer(.library)
        .environment(session)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(before: .windowList) {
                OpenLibraryCommand()
            }
        }
        
        Window("阅读", id: ReaderSession.windowID) {
            ReaderWindow()
        }
        .defaultSize(width: 734, height: 861)
        .environment(session)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        
        SwiftUI.Settings {
            SettingsView()
        }
    }
}

// 退出时先让窗口消失，进程再留一会儿把刚保存的改动传到 iCloud，用户不用等
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ReaderSession()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let start = Date.now
        session.flush()
        guard CloudSync.isActive else { return .terminateNow }
        for window in sender.windows { window.orderOut(nil) }
        Task {
            await SyncMonitor.shared.waitForExport(since: start, timeout: .seconds(10))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct OpenLibraryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("书库") {
            openWindow(id: "library")
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}
