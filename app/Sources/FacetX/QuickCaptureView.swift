import SwiftUI

/// Menu-bar quick-capture: jot one reminder into a project in ~3 seconds without
/// opening the main window. The project decides the target list.
struct QuickCaptureView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var text = ""
    @State private var projectID: Project.ID?
    @State private var justAdded = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private var project: Project? {
        store.activeProjects.first { $0.id == projectID } ?? store.activeProjects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick add").font(.headline)

            if store.activeProjects.isEmpty {
                Text("No projects yet. Open FacetX and create one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { project?.id ?? store.activeProjects.first?.id },
                        set: { projectID = $0 }
                    )) {
                        ForEach(store.activeProjects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 108)

                    Divider().frame(height: 20)

                    TextField("What needs doing?", text: $text)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit(add)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )

                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if justAdded { Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green) }

                HStack {
                    Button("Add") { add() }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty
                                  || targetReminderList.isEmpty)
                    Spacer()
                }
            }

            Divider()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                // Bring the main window forward.
                for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
            } label: {
                Label("Open FacetX", systemImage: "diamond")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            fieldFocused = true
        }
    }

    private var targetReminderList: String {
        nonEmpty(project?.reminderListName) ?? settings.defaultReminderListName
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func add() {
        guard let project else { return }
        let content = text.trimmingCharacters(in: .whitespaces)
        let listName = targetReminderList
        guard !content.isEmpty, !listName.isEmpty else {
            error = "Choose a reminder list for this project."
            return
        }
        error = nil
        let ok = ek.createReminder(project: project.prefix, content: content,
                                   listName: listName, dueDate: nil)
        if ok {
            text = ""
            justAdded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justAdded = false }
        } else {
            error = "Could not save to \(listName)."
        }
    }
}
