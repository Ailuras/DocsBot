import SwiftUI

/// Sheet to edit an existing item (reminder or event) in a project.
struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let item: ProjectItem
    /// Called after a successful save or delete so the detail view can refresh.
    let onUpdated: () -> Void

    @State private var content = ""
    @State private var notes = ""
    @State private var priority: Int = 0
    @State private var useDate = false
    @State private var date = Date()
    @State private var containerName = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(item.kind == .reminder ? "Reminder" : "Event")").font(.title2).bold()

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

            if item.kind == .reminder {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Priority").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $priority) {
                        Text("None").tag(0)
                        Text("Low (!)").tag(9)
                        Text("Medium (!!)").tag(5)
                        Text("High (!!!)").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.kind == .reminder ? "Reminder list" : "Calendar")
                    .font(.caption).foregroundStyle(.secondary)
                
                Picker("", selection: $containerName) {
                    if containerOptions.isEmpty {
                        Text("No options available").tag("")
                    }
                    ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            if item.kind == .reminder {
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
                Button("Delete", role: .destructive) { delete() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty
                              || containerName.isEmpty || saving)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: loadFields)
    }

    private var containerOptions: [String] {
        switch item.kind {
        case .reminder:
            return ek.reminderListNames(enabled: settings.enabledReminderListNames)
        case .event:
            return ek.calendarNames(enabled: settings.enabledCalendarNames)
        }
    }

    private func loadFields() {
        content = item.content
        notes = item.notes ?? ""
        priority = item.priority
        containerName = item.containerName
        if item.kind == .event {
            useDate = true
            date = item.date ?? Date()
        } else if let d = item.date {
            useDate = true
            date = d
        } else {
            useDate = false
            date = Date()
        }
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !containerName.isEmpty else { return }
        saving = true
        error = nil
        let shouldUseDate = item.kind == .event || useDate
        let ok = ek.updateItem(id: item.id, project: project.prefix, content: text,
                               date: shouldUseDate ? date : nil, useDate: shouldUseDate,
                               containerName: containerName, notes: notes.isEmpty ? nil : notes,
                               priority: priority)
        saving = false
        if ok { onUpdated(); dismiss() }
        else { error = "Could not save to \(containerName). Check access." }
    }

    private func delete() {
        saving = true
        error = nil
        let ok = ek.deleteItem(id: item.id)
        saving = false
        if ok { onUpdated(); dismiss() }
        else { error = "Could not delete. Check access." }
    }
}
