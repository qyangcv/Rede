import Foundation
import CloudKit
import CoreData
import Observation
import os

@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()
    static let didImport = Notification.Name("SyncMonitor.didImport")
    private static let log = Logger(subsystem: "Rede", category: "Sync")

    enum Status: Equatable {
        case off
        case noAccount
        case syncing
        case synced
        case failed(String)
    }

    private(set) var lastSynced: Date?
    private var accountAvailable: Bool?
    private var running: [UUID: NSPersistentCloudKitContainer.EventType] = [:]
    private var failures: [NSPersistentCloudKitContainer.EventType: String] = [:]
    private var lastExportStarted: Date?
    private var lastExportFinished: Date?

    private init() {}

    var isImporting: Bool { running.values.contains(.import) }

    var status: Status {
        guard CloudSync.isActive else { return .off }
        if accountAvailable == false { return .noAccount }
        if let failure = failures.values.first { return .failed(failure) }
        return running.isEmpty && lastSynced != nil ? .synced : .syncing
    }

    var hasProblem: Bool {
        switch status {
        case .noAccount, .failed: true
        case .off, .syncing, .synced: false
        }
    }

    var summary: String {
        switch status {
        case .off: "未开启"
        case .noAccount: "未登录 iCloud，或在系统设置中关闭了 Rede 的 iCloud"
        case .syncing: "正在同步…"
        case .synced: "已同步"
        case .failed(let message): message
        }
    }

    func start() {
        guard CloudSync.isActive else { return }
        let center = NotificationCenter.default
        center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                           object: nil, queue: .main) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self.receive(event) }
        }
        center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refreshAccount() }
        }
        refreshAccount()
    }

    func waitForExport(since start: Date, timeout: Duration) async {
        guard CloudSync.isActive else { return }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        let grace = clock.now + .seconds(3)
        while clock.now < deadline {
            if let finished = lastExportFinished, finished >= start { return }
            if (lastExportStarted ?? .distantPast) < start, clock.now > grace { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func refreshAccount() {
        Task {
            guard let status = try? await CKContainer(identifier: CloudSync.container).accountStatus() else { return }
            accountAvailable = status == .available
        }
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        guard let end = event.endDate else {
            running[event.identifier] = event.type
            if event.type == .export { lastExportStarted = event.startDate }
            return
        }
        running[event.identifier] = nil
        if event.type == .export { lastExportFinished = event.startDate }

        if event.succeeded {
            Self.log.info("\(event.description, privacy: .public)")
            failures[event.type] = nil
            if event.type != .setup { lastSynced = end }
            if event.type == .import { NotificationCenter.default.post(name: Self.didImport, object: nil) }
        } else {
            Self.log.error("\(event.description, privacy: .public)")
            failures[event.type] = event.error.map(Self.describe) ?? "同步失败"
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        let inner = error.code == .partialFailure ? error.partialErrorsByItemID?.values.first as? CKError : nil
        switch inner?.code ?? error.code {
        case .quotaExceeded: return "iCloud 空间已满"
        case .notAuthenticated: return "未登录 iCloud"
        case .networkUnavailable, .networkFailure: return "网络不可用，恢复后会自动重试"
        default: return (inner ?? error).localizedDescription
        }
    }
}
