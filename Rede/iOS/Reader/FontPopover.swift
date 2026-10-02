import SwiftUI

// 字体列表：系统菜单行高字号不可调，太占地方，自己画一个紧凑的
struct FontList: View {
    @Binding var selection: ReaderFont

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
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
    }

    private func rows(_ fonts: [ReaderFont]) -> some View {
        ForEach(fonts) { font in
            // 选中后不收起，方便连续试几种字体对照正文
            Button { selection = font } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .opacity(font == selection ? 1 : 0)
                    Text(font.name)
                    Spacer(minLength: 0)
                }
                .frame(height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

// 字体按钮的位置，下拉卡片据此对齐
struct FontButtonAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    // 在字体按钮下方展开卡片。挂在整个面板上而不是按钮上，才能盖住下面几行、不被行高裁掉；
    // 卡片在面板视图树里，亮度遮罩自然压得到
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
                        FontList(selection: selection)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                            .offset(x: button.minX, y: button.maxY + 6)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: isPresented.wrappedValue)
    }
}

#Preview {
    @Previewable @State var font: ReaderFont = .original
    @Previewable @State var shown = true
    @Previewable @State var spacing: Spacing = .standard

    Color.gray.opacity(0.3)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    Text("字体").foregroundStyle(.secondary)
                    Button { shown = true } label: {
                        HStack(spacing: 4) {
                            Text(font.name)
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                        }
                    }
                    .tint(.primary)
                    .font(.footnote)
                    .anchorPreference(key: FontButtonAnchor.self, value: .bounds) { $0 }
                }
                GridRow {
                    Text("行距").foregroundStyle(.secondary)
                    SpacingPicker(title: "行距", selection: $spacing)
                }
                GridRow {
                    Text("段距").foregroundStyle(.secondary)
                    SpacingPicker(title: "段距", selection: $spacing)
                }
                GridRow {
                    Text("外观").foregroundStyle(.secondary)
                    SpacingPicker(title: "外观", selection: $spacing)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .fontDropdown(isPresented: $shown, selection: $font)
            .presentationDetents([.height(400)])
        }
}
