import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let readers = ReaderWindowStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let menu = NSApp.mainMenu else { return }

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
        readers.saveOpenBooks()
        readers.flushAll()
        guard CloudSync.isActive else { return .terminateNow }
        for window in sender.windows { window.orderOut(nil) }
        Task {
            await SyncMonitor.shared.waitForExport(since: start, timeout: .seconds(10))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
