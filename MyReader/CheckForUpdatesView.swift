import SwiftUI
import Sparkle

@Observable
final class CheckForUpdatesViewModel {
    var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            self?.canCheckForUpdates = updater.canCheckForUpdates
        }
    }
}

struct CheckForUpdatesView: View {
    let updater: SPUUpdater
    @State private var model: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = State(initialValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("检查更新…", action: updater.checkForUpdates)
            .disabled(!model.canCheckForUpdates)
    }
}
