import AppKit
import SwiftUI

struct InlineEditTextField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var fontWeight: NSFont.Weight = .regular
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        DispatchQueue.main.async {
            textField.selectText(nil)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditTextField
        var didCancel = false

        init(_ parent: InlineEditTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if didCancel { return }
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                didCancel = true
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

struct ItemRow: View {
    let item: ProjectItem
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    let inlineEditingText: Binding<String>?
    let isInlineEditing: Bool
    let onInlineCommit: (() -> Void)?
    let onInlineCancel: (() -> Void)?

    let inlineEditingNotesText: Binding<String>?
    let isInlineEditingNotes: Bool
    let onInlineNotesCommit: (() -> Void)?
    let onInlineNotesCancel: (() -> Void)?
    let onStartNotesEdit: () -> Void

    @State private var hovered = false

    init(item: ProjectItem,
         isSelected: Bool = false,
         onToggle: @escaping (Bool) -> Void,
         onEdit: @escaping () -> Void,
         inlineEditingText: Binding<String>? = nil,
         isInlineEditing: Bool = false,
         onInlineCommit: (() -> Void)? = nil,
         onInlineCancel: (() -> Void)? = nil,
         inlineEditingNotesText: Binding<String>? = nil,
         isInlineEditingNotes: Bool = false,
         onInlineNotesCommit: (() -> Void)? = nil,
         onInlineNotesCancel: (() -> Void)? = nil,
         onStartNotesEdit: @escaping () -> Void = {}) {
        self.item = item
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.inlineEditingText = inlineEditingText
        self.isInlineEditing = isInlineEditing
        self.onInlineCommit = onInlineCommit
        self.onInlineCancel = onInlineCancel
        self.inlineEditingNotesText = inlineEditingNotesText
        self.isInlineEditingNotes = isInlineEditingNotes
        self.onInlineNotesCommit = onInlineNotesCommit
        self.onInlineNotesCancel = onInlineNotesCancel
        self.onStartNotesEdit = onStartNotesEdit
    }

    private var leftStripeColor: Color {
        switch item.priority {
        case 1...4:
            return .red
        case 5:
            return .orange
        case 6...9:
            return .blue
        default:
            return .clear
        }
    }

    private var borderHighlightColor: Color {
        if item.kind == .reminder && item.priority > 0 {
            return leftStripeColor
        }
        return .blue
    }

    private var rowFill: Color {
        if isSelected { return FacetTheme.softAccent }
        if hovered { return Color.primary.opacity(0.035) }
        return FacetTheme.quietPanel
    }

    private var rowStroke: Color {
        if isSelected { return Color.accentColor.opacity(0.72) }
        if hovered { return borderHighlightColor.opacity(0.32) }
        return FacetTheme.hairline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                if item.kind == .reminder {
                    Button { onToggle(!item.isCompleted) } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if isInlineEditing, let inlineEditingText {
                        InlineEditTextField(text: inlineEditingText,
                                            fontSize: 14,
                                            fontWeight: .semibold,
                                            onCommit: { onInlineCommit?() },
                                            onCancel: { onInlineCancel?() })
                            .frame(minHeight: 22)
                    } else {
                        HStack(spacing: 6) {
                            Text(item.content)
                                .font(.system(size: 13, weight: .medium))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)

                            if let notes = item.notes, !notes.isEmpty {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 1)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if !isInlineEditing, let url = item.url {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.10))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Open link: \(url.absoluteString)")
                    }

                    if let date = item.date {
                        HStack(spacing: 4) {
                            Image(systemName: item.kind == .reminder ? "calendar.badge.clock" : "clock")
                                .font(.system(size: 10))
                            Text(formattedDate(date))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(dateHighlightColor(for: date).opacity(0.10))
                        .foregroundStyle(dateHighlightColor(for: date))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    if !isInlineEditing {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(hovered ? 1.0 : 0.0)
                        .help("Edit item")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .fill(rowFill)
                if item.kind == .reminder && item.priority > 0 {
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .fill(leftStripeColor.opacity(0.025))
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            HStack {
                if item.kind == .reminder && item.priority > 0 {
                    Rectangle()
                        .fill(leftStripeColor)
                        .frame(width: 3)
                }
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(rowStroke, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = isHovered
            }
        }
    }

    private func dateHighlightColor(for date: Date) -> Color {
        if item.isCompleted { return .secondary }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .orange
        } else if date < Date() {
            return .red
        }
        return .secondary
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        let hasTime = item.kind == .event || calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0

        if calendar.isDateInToday(date) {
            if hasTime {
                formatter.dateFormat = "HH:mm"
                return "Today " + formatter.string(from: date)
            } else {
                return "Today"
            }
        } else if calendar.isDateInTomorrow(date) {
            if hasTime {
                formatter.dateFormat = "HH:mm"
                return "Tomorrow " + formatter.string(from: date)
            } else {
                return "Tomorrow"
            }
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            if hasTime {
                formatter.dateFormat = "MMM d HH:mm"
            } else {
                formatter.dateFormat = "MMM d"
            }
            return formatter.string(from: date)
        }
    }
}

struct ItemDropDelegate: DropDelegate {
    let item: ProjectItem
    @Binding var draggedItem: ProjectItem?
    var onMove: (ProjectItem, ProjectItem) -> Void
    var onDrop: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        onDrop()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            onMove(draggedItem, item)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
