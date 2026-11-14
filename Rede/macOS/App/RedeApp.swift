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
        .commandsRemoved()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ReaderSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let menu = NSApp.mainMenu else { return }

        if let edit = menu.items.first(where: { item in
            let commands = item.submenu?.items ?? []
            return commands.contains { $0.action == #selector(NSText.copy(_:)) }
                && commands.contains { $0.action == #selector(NSText.paste(_:)) }
        }), let help = menu.items.first(where: { $0.submenu === NSApp.helpMenu }) {
            menu.removeItem(edit)
            menu.insertItem(edit, at: menu.index(of: help))
        }

        updateMenuTitles(in: menu)
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(menuItemDidUpdate(_:)),
                                                   name: name, object: nil)
        }
    }

    @objc private func menuItemDidUpdate(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
              let item = menu.item(at: index) else { return }
        var rootMenu = menu
        while let parent = rootMenu.supermenu { rootMenu = parent }
        guard rootMenu === NSApp.mainMenu else { return }
        updateMenuTitle(of: item)
    }

    private func updateMenuTitles(in menu: NSMenu) {
        for item in menu.items {
            updateMenuTitle(of: item)
        }
    }

    private func updateMenuTitle(of item: NSMenuItem) {
        if item.title.hasSuffix("…") {
            item.title = String(item.title.dropLast())
        } else if item.title.hasSuffix("...") {
            item.title = String(item.title.dropLast(3))
        }
        if item.title == "全部关闭", item.keyEquivalent == "w",
           item.keyEquivalentModifierMask == [.command, .option], !item.isAlternate {
            item.isAlternate = true
        }
        if let submenu = item.submenu {
            if item.menu === NSApp.mainMenu, submenu.item(withTitle: LibraryDisplayCommands.layoutMenuTitle) != nil {
                if submenu.title != "书库" { submenu.title = "书库" }
                if item.title != "书库" { item.title = "书库" }
            }
            updateMenuTitles(in: submenu)
        }
    }

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

struct OpenLibraryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示书库") {
            openWindow(id: "library")
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}
