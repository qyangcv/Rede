import SwiftUI

struct FontButtonAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    func fontDropdown(isPresented: Binding<Bool>, selection: Binding<ReaderFont>) -> some View {
        overlayPreferenceValue(FontButtonAnchor.self) { anchor in
            if isPresented.wrappedValue, let anchor {
                GeometryReader { proxy in
                    let button = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { isPresented.wrappedValue = false }
                        FontList(current: selection.wrappedValue) {
                            selection.wrappedValue = $0
                            isPresented.wrappedValue = false
                        }
                        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
        .font(.footnote)
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 8)
        .fixedSize()
    }

    private func rows(_ fonts: [ReaderFont]) -> some View {
        ForEach(fonts) { font in
            Button { select(font) } label: {
                HStack(spacing: 0) {
                    Text(font.name)
                    Spacer(minLength: 12)
                    Image(systemName: "checkmark")
                        .opacity(font == current ? 1 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
