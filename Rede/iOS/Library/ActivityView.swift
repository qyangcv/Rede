import SwiftUI

// 系统分享面板。分享前文件已写好，面板据真实文件识别类型；
// ShareLink 的延迟文件表示在多选时会被识别成纯文本
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
