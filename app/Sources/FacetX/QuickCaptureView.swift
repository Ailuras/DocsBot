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
                    .frame(width: 106, alignment: .leading)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 1, height: 18)

                    TextField("What needs doing?", text: $text)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit(add)
                }
                .padding(.leading, 6)
                .padding(.trailing, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12))
                )

                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if justAdded { Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green) }
            }

            Divider()
            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    // Bring the main window forward.
                    let windows = NSApp.windows.filter { $0.canBecomeMain }
                    if windows.isEmpty {
                        NSWorkspace.shared.open(Bundle.main.bundleURL)
                    } else {
                        for w in windows { w.makeKeyAndOrderFront(nil) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: MenuBarController.templateImage())
                            .resizable()
                            .frame(width: 14, height: 14)
                            .opacity(0.62)
                        Text("Open FacetX")
                    }
                    .foregroundStyle(.primary.opacity(0.82))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .foregroundStyle(.primary.opacity(0.68))
                }
                .buttonStyle(.plain)
            }
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
