import SwiftUI

struct FontsPane: View {
    var body: some View {
        Form {
            Section {
                ForEach(ReaderFont.allCases) { font in
                    if let package = font.package {
                        FontRow(font: font, package: package)
                    }
                }
            } header: {
                Text("第三方字体")
            } footer: {
                Text("下载字体需要确保网络能够访问 GitHub")
            }
        }
        .formStyle(.grouped)
    }
}

private struct FontRow: View {
    let font: ReaderFont
    let package: FontPackage

    private var store: FontStore { .shared }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(font.name)
                HStack(spacing: 0) {
                    // 行内的按钮都要显式指定样式：iOS 列表行里的默认样式按钮会让整行变成一个点击区域，点"下载"也会打开链接
                    Link(package.author, destination: package.repository)
                        .buttonStyle(.borderless)
                    Text(" · \(package.license) · \(package.size.formatted(.byteCount(style: .file)))").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        if let received = store.received[font] {
            ProgressView(value: Double(received), total: Double(package.size))
                .frame(width: 100)
            Button("取消", systemImage: "xmark.circle.fill") { store.cancel(font) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        } else if store.downloaded.contains(font) {
            Button("删除", role: .destructive) { store.delete(font) }
                .buttonStyle(.bordered)
        } else {
            if store.failed.contains(font) {
                Text("下载失败").font(.caption).foregroundStyle(.red)
            }
            Button("下载") { store.download(font) }
                .buttonStyle(.bordered)
        }
    }
}