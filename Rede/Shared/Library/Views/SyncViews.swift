import SwiftUI

// 书库顶部的同步提示：从 iCloud 下载时显示，完成后提示"已同步"，两秒后消失；不拦截点击，书照常能打开
struct SyncBanner: View {
    // 横幅自己的显示阶段，不直接等于 isImporting：系统启动、回前台时常连着跑几轮 import，
    // 中间只隔零点几秒，要合并成一次"同步中 → 已同步"
    private enum Phase {
        case syncing, done

        var title: String { self == .syncing ? "正在从 iCloud 同步…" : "已同步" }
        var symbol: String { self == .syncing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud" }
    }

    @State private var phase: Phase?

    private var monitor: SyncMonitor { .shared }

    var body: some View {
        Group {
            // 两个阶段共用一个胶囊，切换时原地变宽窄，不会两个胶囊交叉淡化
            if let phase {
                Label {
                    Text(phase.title)
                } icon: {
                    // 同步中只转箭头、云不动。rotate 的 isActive 置为 false 后不会停（iOS 26.5 实测），
                    // 换成对勾云后整朵云跟着转；按阶段换掉图标身份才能停下，对勾用 drawOn 画出来
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
        // isImporting 一变就取消上一次任务：等待期间新一轮 import 开始，横幅就继续停在"同步中"
        .task(id: monitor.isImporting) {
            if monitor.isImporting { phase = .syncing; return }
            guard phase == .syncing else { return }
            guard !monitor.hasProblem else { phase = nil; return }
            do {
                // 结束后先停一秒，看还有没有下一轮；这一秒也让"同步中"不会一闪而过
                try await Task.sleep(for: .seconds(1))
                phase = .done
                try await Task.sleep(for: .seconds(2))
                phase = nil
            } catch {}
        }
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
