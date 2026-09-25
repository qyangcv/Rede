import SwiftUI
import SwiftData
import Sparkle

@main
struct RedeApp: App {
    @State private var session = ReaderSession()
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
        NSApplication.shared.appearance = Settings.shared.appearance.nsAppearance
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
    }
    
    var body: some Scene {
        Window("书库", id: "library") {
            ContentView()
        }
        .defaultSize(width: 600, height: 400)
        .modelContainer(.localLibrary)
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
