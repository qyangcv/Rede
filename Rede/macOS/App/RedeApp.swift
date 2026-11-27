import SwiftUI
import SwiftData
import Sparkle

@main
struct RedeApp: App {
    static let libraryWindowID = "library"
    static let readerWindowID = "reader"
    private static let libraryFrameName: NSWindow.FrameAutosaveName = "Rede.Library"
    private static let readerFrameName: NSWindow.FrameAutosaveName = "Rede.Reader"

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private var readers: ReaderWindowStore { appDelegate.readers }
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
        Window("书库", id: Self.libraryWindowID) {
            LibraryView()
                .background(WindowFramePersistence(name: Self.libraryFrameName))
        }
        .defaultWindowPlacement { _, context in
            WindowFramePersistence.placement(for: Self.libraryFrameName, in: context) {
                let bounds = context.defaultDisplay.bounds
                let size = CGSize(width: 600, height: 400)
                let position = CGPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.midY - size.height / 2
                )
                return WindowPlacement(position, size: size)
            }
        }
        .restorationBehavior(.disabled)
        .modelContainer(.library)
        .environment(readers)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .appSettings) {
                SettingsLink { Text("设置") }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                LibraryFileCommands()
            }
            CommandGroup(replacing: .saveItem) {
                CloseWindowCommands()
            }
            CommandGroup(before: .toolbar) {
                LibraryDisplayCommands()
            }
            CommandMenu("阅读") {
                ReaderMenuCommands()
            }
            CommandMenu("样式") {
                ReaderStyleCommands()
            }
            CommandGroup(before: .windowList) {
                OpenLibraryCommand()
            }
        }

        WindowGroup("阅读", id: Self.readerWindowID, for: UUID.self) { $windowID in
            if let windowID {
                ReaderWindow(windowID: windowID)
                    .background(WindowFramePersistence(name: Self.readerFrameName, cascading: true))
            }
        }
        .defaultWindowPlacement { _, context in
            WindowFramePersistence.placement(for: Self.readerFrameName, cascading: true, in: context) {
                let bounds = context.defaultDisplay.bounds
                let scale: CGFloat = 3.0 / 4.0
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let position = CGPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.midY - size.height / 2
                )
                return WindowPlacement(position, size: size)
            }
        }
        .environment(readers)
        .windowManagerRole(.principal)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        SwiftUI.Settings {
            SettingsView()
        }
        .commandsRemoved()
    }
}

private struct CloseWindowCommands: View {
    @State private var canClose = false

    var body: some View {
        Button("关闭窗口") {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("w")
        .disabled(!canClose)
        .onAppear(perform: updateAvailability)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            updateAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            updateAvailability()
        }

        Button("全部关闭") {
            for window in NSApp.windows where window.isVisible || window.isMiniaturized {
                if window.styleMask.contains(.closable) { window.performClose(nil) }
            }
        }
        .keyboardShortcut("w", modifiers: [.command, .option])
        .disabled(!canClose)
    }

    private func updateAvailability() {
        let window = NSApp.target(forAction: #selector(NSWindow.performClose(_:))) as? NSWindow
        canClose = window?.styleMask.contains(.closable) == true
    }
}
