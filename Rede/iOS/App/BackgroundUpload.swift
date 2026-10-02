import UIKit

final class BackgroundUpload {
    static let shared = BackgroundUpload()

    private var task: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func begin() {
        guard CloudSync.isActive, task == .invalid else { return }
        let start = Date.now
        task = UIApplication.shared.beginBackgroundTask(withName: "iCloud 上传") { [weak self] in
            self?.end()
        }
        Task {
            await SyncMonitor.shared.waitForExport(since: start, timeout: .seconds(25))
            end()
        }
    }

    private func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
