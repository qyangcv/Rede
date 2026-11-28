import SwiftUI

struct ImportProgressRing: View {
    let progress: ImportProgress

    private var fraction: Double {
        guard progress.total > 0 else { return 0 }
        return max(Double(progress.completed) / Double(progress.total), 0.08)
    }

    var body: some View {
        if progress.total > 1 {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress.completed)
            }
            .frame(width: 15, height: 15)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}
