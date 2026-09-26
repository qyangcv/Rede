import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("字体", systemImage: "f.cursive") {
                FontsPane()
            }
        }
    }
}

struct FontsPane: View {
    var body: some View {
        Form {
            Section("第三方字体") {
                ForEach(ReaderFont.allCases) { font in
                    if let package = font.package {
                        FontRow(font: font, package: package)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
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
                    Link(package.author, destination: package.repository)
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
        } else {
            if store.failed.contains(font) {
                Text("下载失败").font(.caption).foregroundStyle(.red)
            }
            Button("下载") { store.download(font) }
        }
    }
}

#Preview {
    SettingsView()
}
