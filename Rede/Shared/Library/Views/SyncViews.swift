import SwiftUI

struct SyncBanner: View {
    private enum Phase {
        case syncing, done

        var title: String { self == .syncing ? "正在从 iCloud 同步…" : "已同步" }
        var symbol: String { self == .syncing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud" }
    }

    @State private var phase: Phase?

    private var monitor: SyncMonitor { .shared }

    var body: some View {
        Group {
            if let phase {
                Label {
                    Text(phase.title)
                } icon: {
                    Image(systemName: phase.symbol)
                        .symbolEffect(.rotate.byLayer, isActive: phase == .syncing)
                        .id(phase)
                        .transition(.symbolEffect(.drawOn))
                }
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.default, value: phase)
        .task(id: monitor.isImporting) {
            if monitor.isImporting { phase = .syncing; return }
            guard phase == .syncing else { return }
            guard !monitor.hasProblem else { phase = nil; return }
            do {
                try await Task.sleep(for: .seconds(1))
                phase = .done
                try await Task.sleep(for: .seconds(2))
                phase = nil
            } catch {}
        }
    }
}

struct SyncAlertButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("iCloud 同步出错", systemImage: "exclamationmark.icloud") { isPresented = true }
            .help("iCloud 同步出错")
            .popover(isPresented: $isPresented) {
                Text(SyncMonitor.shared.summary)
                    .frame(width: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
    }
}
