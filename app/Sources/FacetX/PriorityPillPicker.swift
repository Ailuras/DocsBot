import SwiftUI

struct PriorityPillPicker: View {
    @Binding var selection: Int

    private let options = [
        PriorityOption(value: 0, title: "None"),
        PriorityOption(value: 9, title: "Low"),
        PriorityOption(value: 5, title: "Med"),
        PriorityOption(value: 1, title: "High")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: selection == option.value ? .semibold : .medium))
                        .foregroundStyle(selection == option.value ? Color.white : Color.primary.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selection == option.value ? priorityColor(option.value) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(FacetTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func priorityColor(_ value: Int) -> Color {
        switch value {
        case 1...4: return .red
        case 5: return .blue
        case 6...9: return .orange
        default: return .secondary
        }
    }

    private struct PriorityOption: Identifiable {
        let value: Int
        let title: String

        var id: Int { value }
    }
}
