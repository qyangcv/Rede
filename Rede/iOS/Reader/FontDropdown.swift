import SwiftUI

// 字体下拉卡片。不用系统菜单：系统菜单行高字号不可调，太占地方；
// 而且它单独弹出，不在面板视图树里，亮度遮罩压不到

// 字体按钮的位置，下拉卡片据此对齐
struct FontButtonAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    // 在字体按钮下方展开卡片。挂在整个面板上而不是按钮上，才能盖住下面几行、不被行高裁掉
    func fontDropdown(isPresented: Binding<Bool>, selection: Binding<ReaderFont>) -> some View {
        overlayPreferenceValue(FontButtonAnchor.self) { anchor in
            if isPresented.wrappedValue, let anchor {
                GeometryReader { proxy in
                    let button = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        // 点卡片外任意处收起，这次点击不传给下面的控件
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { isPresented.wrappedValue = false }
                        FontList(current: selection.wrappedValue) {
                            selection.wrappedValue = $0
                            isPresented.wrappedValue = false
                        }
                        // 底色与分段控件选中的胶囊一致：浅色为白，深色为抬升的灰；面板底色相近，靠阴影分层
                        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        // 左移一个内边距，列表里的字体名与按钮上的字体名对齐
                        .offset(x: button.minX - FontList.inset, y: button.maxY + 6)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: isPresented.wrappedValue)
    }
}

private struct FontList: View {
    static let inset: CGFloat = 14

    let current: ReaderFont
    let select: (ReaderFont) -> Void

    var body: some View {
        let fonts = ReaderFont.allCases.filter(\.isAvailable)
        VStack(alignment: .leading, spacing: 0) {
            rows(fonts.filter(\.isBuiltin))
            let thirdParty = fonts.filter { !$0.isBuiltin }
            if !thirdParty.isEmpty {
                Divider().padding(.vertical, 4)
                rows(thirdParty)
            }
        }
        // 与面板里字体按钮同字号
        .font(.footnote)
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 8)
        .fixedSize()
    }

    private func rows(_ fonts: [ReaderFont]) -> some View {
        ForEach(fonts) { font in
            Button { select(font) } label: {
                // Spacer 两侧都会算一次 HStack 间距，所以间距置零、只用 Spacer 的最小宽度
                HStack(spacing: 0) {
                    Text(font.name)
                    Spacer(minLength: 12)
                    Image(systemName: "checkmark")
                        .opacity(font == current ? 1 : 0)
                }
                // 撑满卡片宽度，字体名长短不一时对勾仍对齐在右侧
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
