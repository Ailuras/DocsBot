import FacetXCore
import SwiftUI

/// Sheet to create a new item in a project. The app composes the
/// `ProjectName:` prefix automatically, so the user only types the content —
/// the project-association contract is enforced by construction, not by the
/// user remembering to prefix.
struct CreateItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    /// Called after a successful create so the detail view can refresh.
    let onCreated: () -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case reminder = "Reminder", event = "Event"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .reminder
    @State private var content = ""
    @State private var notes = ""
    @State private var priority: Int = 0
    @State private var useDate = false
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to \(project.name)").font(.title2).bold()

            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.caption).foregroundStyle(.secondary)
                TextField("What needs doing?", text: $content)
                    .textFieldStyle(.roundedBorder)
                Text("Will be saved as “\(ProjectPrefix.makeTitle(project: project.prefix, content: content.isEmpty ? "…" : content))”.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("Add details...", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }

            if kind == .reminder {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Priority").font(.caption).foregroundStyle(.secondary)
                    PriorityPillPicker(selection: $priority)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .reminder ? "Reminder list" : "Calendar")
                    .font(.caption).foregroundStyle(.secondary)
                Label(targetContainer.isEmpty ? "No default selected" : targetContainer,
                      systemImage: kind == .reminder ? "list.bullet" : "calendar")
                    .foregroundStyle(targetContainer.isEmpty ? .red : .secondary)
            }

            if kind == .reminder {
                Toggle("Due date", isOn: $useDate)
                if useDate {
                    DatePicker("", selection: $date, displayedComponents: [.date])
                        .labelsHidden()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start date").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty
                              || targetContainer.isEmpty || saving)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var targetContainer: String {
        switch kind {
        case .reminder:
            return nonEmpty(project.reminderListName) ?? settings.defaultReminderListName
        case .event:
            return nonEmpty(project.calendarName) ?? settings.defaultCalendarName
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespaces)
        let container = targetContainer
        guard !text.isEmpty, !container.isEmpty else { return }
        saving = true
        error = nil
        Task {
            let ok: Bool
            switch kind {
            case .reminder:
                ok = await ek.createReminder(project: project.prefix, content: text,
                                             listName: container, dueDate: useDate ? date : nil,
                                             notes: notes.isEmpty ? nil : notes,
                                             priority: priority) != nil
            case .event:
                ok = await ek.createEvent(project: project.prefix, content: text,
                                          calendarName: container, startDate: date,
                                          notes: notes.isEmpty ? nil : notes)
            }
            saving = false
            if ok { onCreated(); dismiss() }
            else { error = "Could not save to \(container). Check access." }
        }
    }
}
