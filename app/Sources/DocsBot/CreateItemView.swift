import SwiftUI

/// Sheet to create a new item in a project. The app composes the
/// `ProjectName:` prefix automatically, so the user only types the content —
/// the project-association contract is enforced by construction, not by the
/// user remembering to prefix.
struct CreateItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService

    let project: Project
    /// Called after a successful create so the detail view can refresh.
    let onCreated: () -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case reminder = "Reminder", event = "Event"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .reminder
    @State private var content = ""
    @State private var container = ""
    @State private var useDate = false
    @State private var date = Date()
    @State private var containers: [String] = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add to \(project.name)").font(.title2).bold()

            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in reloadContainers() }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content").font(.caption).foregroundStyle(.secondary)
                TextField("What needs doing?", text: $content)
                    .textFieldStyle(.roundedBorder)
                Text("Will be saved as “\(ProjectPrefix.makeTitle(project: project.prefix, content: content.isEmpty ? "…" : content))”.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .reminder ? "List" : "Calendar (functional zone)")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $container) {
                    ForEach(containers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            Toggle(kind == .reminder ? "Due date" : "Start date", isOn: $useDate)
            if useDate {
                DatePicker("", selection: $date,
                           displayedComponents: kind == .reminder ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty
                              || container.isEmpty || saving)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: reloadContainers)
    }

    private func reloadContainers() {
        containers = kind == .reminder ? ek.reminderListNames() : ek.calendarNames()
        if !containers.contains(container) { container = containers.first ?? "" }
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !container.isEmpty else { return }
        saving = true
        error = nil
        let ok: Bool
        switch kind {
        case .reminder:
            ok = ek.createReminder(project: project.prefix, content: text,
                                   listName: container, dueDate: useDate ? date : nil)
        case .event:
            ok = ek.createEvent(project: project.prefix, content: text,
                                calendarName: container, startDate: useDate ? date : Date())
        }
        saving = false
        if ok { onCreated(); dismiss() }
        else { error = "Could not save to \(container). Check access." }
    }
}
