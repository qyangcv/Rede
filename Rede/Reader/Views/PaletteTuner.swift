#if DEBUG
import SwiftUI

// 开发者调色：输入完整色值即实时覆盖当前主题，清空则恢复
@Observable
final class PaletteTuner {
    static let shared = PaletteTuner()

    var background = ""
    var text = ""

    func apply(to vars: inout [String: String], scheme: ColorScheme) {
        if Self.isHex(background) { vars["--reader-bg"] = background }
        if Self.isHex(text) { vars[scheme == .dark ? "--USER__textColor" : "--RS__textColor"] = text }
    }

    private static func isHex(_ value: String) -> Bool {
        value.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil
    }
}

struct PaletteTunerPanel: View {
    @Bindable private var tuner = PaletteTuner.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            TextField("背景", text: $tuner.background,
                      prompt: Text(Settings.shared.readerStyle.background.color(for: colorScheme)))
            TextField("文字", text: $tuner.text, prompt: Text(TextColor.color(for: colorScheme)))
        }
        .formStyle(.grouped)
        .monospaced()
        .frame(width: 260)
    }
}

struct PaletteTunerButton: View {
    var onDismiss: () -> Void = {}

    @State private var isPresented = false

    var body: some View {
        Button("调色", systemImage: "paintpalette") {
            isPresented.toggle()
        }
        .help("调色")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PaletteTunerPanel()
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { onDismiss() }
        }
    }
}
#endif
