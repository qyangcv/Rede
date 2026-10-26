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
        #if DEBUG
        if CommandLine.arguments.contains(CloudKitSchema.argument) {
            do {
                try CloudKitSchema.initialize()
                exit(0)
            } catch {
                print(error)
                exit(1)
            }
        }
        #endif
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
            CommandGroup(before: .toolbar) {
                LibraryLayoutCommands()
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

struct LibraryLayoutCommands: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Picker("陈列方式", selection: $settings.libraryLayout) {
            Text("以卡片方式").tag(LibraryLayout.grid).keyboardShortcut("1")
            Text("以列表方式").tag(LibraryLayout.list).keyboardShortcut("2")
        }
        .pickerStyle(.inline)
    }
}
