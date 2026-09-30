import SwiftUI

// 书库顶部的下载提示：从 iCloud 下载时显示，完成后提示"已同步"，两秒后消失；不拦截点击，书照常能打开
struct SyncBanner: View {
    @State private var showsDone = false

    private var monitor: SyncMonitor { .shared }

    var body: some View {
        Group {
            if monitor.isImporting {
                label("正在从 iCloud 同步…", systemImage: "arrow.triangle.2.circlepath.icloud")
            } else if showsDone {
                label("已同步", systemImage: "checkmark.icloud")
            }
        }
        .allowsHitTesting(false)
        .animation(.default, value: monitor.isImporting)
        .animation(.default, value: showsDone)
        .onChange(of: monitor.isImporting) { _, importing in
            guard !importing, !monitor.hasProblem else { return }
            showsDone = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showsDone = false
            }
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect()
            .padding(.top, 8)
            .transition(.opacity)
    }
}

// 同步出了问题（未登录 iCloud、空间已满、服务器拒绝等）时出现在书库工具栏，点开看原因
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
