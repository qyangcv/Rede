import AppKit
import SwiftUI

enum MarginSide: Equatable {
    case leading
    case trailing
}

struct MarginNotesLayout: Equatable {
    static let leadingGap: CGFloat = 15
    static let trailingPadding: CGFloat = 15
    static let minCardWidth: CGFloat = 150
    static let maxCardWidth: CGFloat = 300
    static let itemSpacing: CGFloat = 10

    let leadingX: CGFloat
    let leadingWidth: CGFloat
    let trailingX: CGFloat
    let trailingWidth: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    var height: CGFloat { max(bottom - top, 0) }
    var hasLeading: Bool { leadingWidth >= Self.minCardWidth }

    init?(viewport: PageViewport) {
        guard viewport.columns == 1 else { return nil }
        let trailingAvailable = CGFloat(viewport.width - viewport.contentRight) - Self.leadingGap - Self.trailingPadding
        guard trailingAvailable >= Self.minCardWidth else { return nil }
        let top = CGFloat(viewport.contentTop)
        let bottom = CGFloat(viewport.contentBottom)
        guard bottom > top else { return nil }

        let trailingWidth = min(trailingAvailable, Self.maxCardWidth)
        let leadingAvailable = CGFloat(viewport.contentLeft) - Self.leadingGap - Self.trailingPadding
        let leadingWidth = leadingAvailable >= Self.minCardWidth ? min(leadingAvailable, Self.maxCardWidth) : 0

        self.leadingWidth = leadingWidth
        self.leadingX = CGFloat(viewport.contentLeft) - Self.leadingGap - leadingWidth
        self.trailingWidth = trailingWidth
        self.trailingX = CGFloat(viewport.contentRight) + Self.leadingGap
        self.top = top
        self.bottom = bottom
    }

    func split(_ items: [MarginNoteItem]) -> (leading: [MarginNoteItem], trailing: [MarginNoteItem]) {
        guard hasLeading else { return ([], items) }
        var leading: [MarginNoteItem] = []
        var trailing: [MarginNoteItem] = []
        var leadingCursor = top
        var trailingCursor = top
        let nominalHeight: CGFloat = 36

        for item in items {
            let desiredTop = max(top, item.anchorMidY - nominalHeight / 2)
            let isCenteredWide = item.widthRatio >= 0.5 && item.midX >= 0.4 && item.midX <= 0.6
            let side: MarginSide
            if isCenteredWide {
                let trailingCollides = trailingCursor > desiredTop
                let leadingCollides = leadingCursor > desiredTop
                side = (trailingCollides && !leadingCollides) ? .leading : .trailing
            } else {
                side = item.midX < 0.5 ? .leading : .trailing
            }

            switch side {
            case .leading:
                leading.append(item)
                leadingCursor = max(desiredTop, leadingCursor) + nominalHeight + Self.itemSpacing
            case .trailing:
                trailing.append(item)
                trailingCursor = max(desiredTop, trailingCursor) + nominalHeight + Self.itemSpacing
            }
        }
        return (leading, trailing)
    }

    func place(anchors: [CGFloat], heights: [CGFloat]) -> (offsets: [CGFloat], contentHeight: CGFloat) {
        guard !anchors.isEmpty else { return ([], height) }
        var ys = [CGFloat]()
        ys.reserveCapacity(anchors.count)
        var cursor = top
        for i in anchors.indices {
            let centered = anchors[i] - heights[i] / 2
            let y = max(centered, cursor)
            ys.append(y)
            cursor = y + heights[i] + Self.itemSpacing
        }

        if let lastY = ys.last, let lastH = heights.last, lastY + lastH > bottom {
            for i in stride(from: ys.count - 1, through: 0, by: -1) {
                let limit = i == ys.count - 1 ? bottom : ys[i + 1] - Self.itemSpacing
                if ys[i] + heights[i] > limit {
                    ys[i] = limit - heights[i]
                }
            }
            if ys[0] < top {
                var packed = top
                for i in ys.indices {
                    ys[i] = packed
                    packed += heights[i] + Self.itemSpacing
                }
            }
        }

        let totalEnd = (ys.last ?? top) + (heights.last ?? 0)
        return (ys.map { $0 - top }, max(height, totalEnd - top))
    }
}

struct MarginNoteItem: Identifiable, Equatable {
    let id: String
    let note: String
    let color: HighlightColor
    let anchorMidY: CGFloat
    let midX: Double
    let widthRatio: Double
}

struct MarginNotesOverlay: View {
    let layout: MarginNotesLayout
    let items: [MarginNoteItem]
    @Binding var editingID: String?
    @Binding var hoveredID: String?
    let onSave: (String, String) -> Void
    let onChangeColor: (String, HighlightColor) -> Void
    let onDelete: (String) -> Void
    let onFinishEditing: () -> Void

    @State private var heights: [String: CGFloat] = [:]

    var body: some View {
        if !items.isEmpty {
            let columns = layout.split(items)
            ZStack {
                if layout.hasLeading, !columns.leading.isEmpty {
                    column(items: columns.leading, side: .leading, x: layout.leadingX, width: layout.leadingWidth)
                }
                if !columns.trailing.isEmpty {
                    column(items: columns.trailing, side: .trailing, x: layout.trailingX, width: layout.trailingWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: items.map(\.id)) { _, ids in
                let valid = Set(ids)
                heights = heights.filter { valid.contains($0.key) }
            }
        }
    }

    private func column(items: [MarginNoteItem], side: MarginSide, x: CGFloat, width: CGFloat) -> some View {
        let measured = items.map { heights[$0.id] ?? ($0.id == editingID ? 116 : 36) }
        let placement = layout.place(anchors: items.map(\.anchorMidY), heights: measured)
        let needsScroll = placement.contentHeight > layout.height + 1

        return Group {
            if needsScroll {
                ScrollView(.vertical) {
                    cardsStack(items: items, side: side, width: width,
                               offsets: placement.offsets, contentHeight: placement.contentHeight)
                }
                .scrollIndicators(.automatic)
            } else {
                cardsStack(items: items, side: side, width: width,
                           offsets: placement.offsets, contentHeight: layout.height)
            }
        }
        .frame(width: width, height: layout.height, alignment: .topLeading)
        .position(x: x + width / 2, y: layout.top + layout.height / 2)
    }

    private func cardsStack(items: [MarginNoteItem], side: MarginSide, width: CGFloat,
                            offsets: [CGFloat], contentHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MarginNoteCard(
                    item: item,
                    side: side,
                    isEditing: editingID == item.id,
                    isHovered: hoveredID == item.id,
                    onHover: { hovered in
                        if hovered {
                            hoveredID = item.id
                        } else if hoveredID == item.id {
                            hoveredID = nil
                        }
                    },
                    onStartEditing: {
                        editingID = item.id
                    },
                    onSave: { text in
                        onSave(item.id, text)
                    },
                    onChangeColor: { color in
                        onChangeColor(item.id, color)
                    },
                    onDelete: {
                        if editingID == item.id { editingID = nil }
                        if hoveredID == item.id { hoveredID = nil }
                        onDelete(item.id)
                    },
                    onFinishEditing: {
                        if editingID == item.id { editingID = nil }
                        onFinishEditing()
                    }
                )
                .frame(width: width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs((heights[item.id] ?? 0) - height) > 0.5 {
                        heights[item.id] = height
                    }
                }
                .offset(y: offsets[index])
            }
        }
        .frame(width: width, height: contentHeight, alignment: .topLeading)
    }
}

private struct MarginNoteCard: View {
    let item: MarginNoteItem
    let side: MarginSide
    let isEditing: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onStartEditing: () -> Void
    let onSave: (String) -> Void
    let onChangeColor: (HighlightColor) -> Void
    let onDelete: () -> Void
    let onFinishEditing: () -> Void

    @State private var draft: String
    @State private var hasInput = false
    @State private var deleted = false

    init(item: MarginNoteItem, side: MarginSide, isEditing: Bool, isHovered: Bool,
         onHover: @escaping (Bool) -> Void, onStartEditing: @escaping () -> Void,
         onSave: @escaping (String) -> Void, onChangeColor: @escaping (HighlightColor) -> Void,
         onDelete: @escaping () -> Void, onFinishEditing: @escaping () -> Void) {
        self.item = item
        self.side = side
        self.isEditing = isEditing
        self.isHovered = isHovered
        self.onHover = onHover
        self.onStartEditing = onStartEditing
        self.onSave = onSave
        self.onChangeColor = onChangeColor
        self.onDelete = onDelete
        self.onFinishEditing = onFinishEditing
        _draft = State(initialValue: item.note)
        _hasInput = State(initialValue: !item.note.isEmpty)
    }

    var body: some View {
        if isEditing {
            editor
        } else {
            preview
        }
    }

    private var accentBar: some View {
        Capsule()
            .fill(item.color.accent.opacity(isHovered ? 0.95 : 0.6))
            .frame(width: 2)
            .padding(.vertical, 2)
    }

    private var previewText: some View {
        Text(item.note)
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(.primary.opacity(isHovered ? 0.92 : 0.72))
            .lineLimit(8)
            .multilineTextAlignment(side == .leading ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: side == .leading ? .trailing : .leading)
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 8) {
            if side == .leading {
                previewText
                accentBar
            } else {
                accentBar
                previewText
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onStartEditing)
        .onHover(perform: onHover)
        .contextMenu {
            Button("编辑笔记", systemImage: "pencil", action: onStartEditing)
            Menu("更改颜色", systemImage: "paintpalette") {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        onChangeColor(color)
                    } label: {
                        Label(color.name, systemImage: color == item.color ? "checkmark" : "circle.fill")
                    }
                }
            }
            Divider()
            Button("移除高亮与笔记", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if !hasInput {
                    Text("添加笔记…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                MarginNoteTextView(
                    text: $draft,
                    hasInput: $hasInput,
                    onCancel: commit,
                    onEndEditing: commit
                )
                .frame(height: 84)
            }
            HStack(spacing: 4) {
                HighlightColorDots(selection: item.color, size: 12, spacing: 6, onSelect: onChangeColor)

                Spacer(minLength: 4)

                Button(role: .destructive) {
                    deleted = true
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(item.note.isEmpty ? "移除高亮" : "移除高亮与笔记")
                .accessibilityLabel(item.note.isEmpty ? "移除高亮" : "移除高亮与笔记")

                Button(action: commit) {
                    Image(systemName: "checkmark")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("完成")
                .accessibilityLabel("完成")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: side == .leading ? .trailing : .leading) {
            Capsule()
                .fill(item.color.accent.opacity(0.85))
                .frame(width: 2)
                .padding(.vertical, 8)
        }
        .onAppear {
            draft = item.note
            hasInput = !item.note.isEmpty
            deleted = false
        }
        .onDisappear {
            if !deleted { onSave(draft) }
        }
    }

    private func commit() {
        guard !deleted else { return }
        onSave(draft)
        onFinishEditing()
    }
}

private struct MarginNoteTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var hasInput: Bool
    let onCancel: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = style
        textView.font = NSFont.systemFont(ofSize: 12.5)
        textView.textColor = .labelColor
        textView.string = text
        textView.onMarkedTextChange = { [weak coordinator = context.coordinator] hasMarked in
            coordinator?.updateInputState(hasMarked: hasMarked)
        }
        textView.onCancel = onCancel

        scrollView.documentView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        textView.onCancel = onCancel
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            hasInput = !text.isEmpty
        }
    }

    final class EditorTextView: NSTextView {
        var onMarkedTextChange: ((Bool) -> Void)?
        var onCancel: (() -> Void)?

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onMarkedTextChange?(hasMarkedText())
        }

        override func unmarkText() {
            super.unmarkText()
            onMarkedTextChange?(hasMarkedText())
        }

        override func cancelOperation(_ sender: Any?) {
            onCancel?()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarginNoteTextView
        private var hasMarked = false

        init(_ parent: MarginNoteTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            hasMarked = textView.hasMarkedText()
            parent.text = textView.string
            parent.hasInput = !textView.string.isEmpty || hasMarked
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        func updateInputState(hasMarked: Bool) {
            self.hasMarked = hasMarked
            let active = !parent.text.isEmpty || hasMarked
            if parent.hasInput != active {
                parent.hasInput = active
            }
        }
    }
}
