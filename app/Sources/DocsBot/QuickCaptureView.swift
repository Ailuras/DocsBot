import SwiftUI

/// Menu-bar quick-capture: jot one item into a project in ~3 seconds without
/// opening the main window. The `ProjectName:` prefix is composed automatically.
struct QuickCaptureView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: Settings

    @State private var text = ""
    @State private var projectID: Project.ID?
    @State private var kind: CreateKind = .reminder
    @State private var container = ""
    @State private var containers: [String] = []
    @State private var justAdded = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    enum CreateKind: String, CaseIterable, Identifiable {
        case reminder = "Reminder", event = "Event"
        var id: String { rawValue }
    }

    private var project: Project? {
        store.activeProjects.first { $0.id == projectID } ?? store.activeProjects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick add").font(.headline)

            if store.activeProjects.isEmpty {
                Text("No projects yet. Open DocsBot and declare one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("What needs doing?", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(add)

                HStack {
                    Picker("", selection: Binding(
                        get: { project?.id ?? store.activeProjects.first?.id },
                        set: { projectID = $0 }
                    )) {
                        ForEach(store.activeProjects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()

                    Picker("", selection: $kind) {
                        ForEach(CreateKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .onChange(of: kind) { _, _ in reloadContainers() }
                }

                Picker("Into", selection: $container) {
                    ForEach(containers, id: \.self) { Text($0).tag($0) }
                }

                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if justAdded { Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green) }

                HStack {
                    Button("Add") { add() }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || container.isEmpty)
                    Spacer()
                }
            }

            Divider()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                // Bring the main window forward.
                for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
            } label: {
                Label("Open DocsBot", systemImage: "diamond")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            reloadContainers()
            fieldFocused = true
        }
    }

    private func reloadContainers() {
        let enabled = settings.enabledContainerNames
        containers = kind == .reminder
            ? ek.reminderListNames(enabled: enabled)
            : ek.calendarNames(enabled: enabled)
        if !containers.contains(container) { container = containers.first ?? "" }
    }

    private func add() {
        guard let project else { return }
        let content = text.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty, !container.isEmpty else { return }
        error = nil
        let ok: Bool
        switch kind {
        case .reminder:
            ok = ek.createReminder(project: project.prefix, content: content,
                                   listName: container, dueDate: nil)
        case .event:
            ok = ek.createEvent(project: project.prefix, content: content,
                                calendarName: container, startDate: Date())
        }
        if ok {
            text = ""
            justAdded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justAdded = false }
        } else {
            error = "Could not save to \(container)."
        }
    }
}
