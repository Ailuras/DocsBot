import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedID: Project.ID?
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?
    @State private var editingProject: Project?

    private var selected: Project? {
        store.activeProjects.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    Section("Projects") {
                        ForEach(store.activeProjects) { project in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name).font(.headline)
                                if !project.tagline.isEmpty {
                                    Text(project.tagline)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tag(project.id)
                            .contextMenu {
                                Button("Edit Project") {
                                    selectedID = project.id
                                    editingProject = project
                                }
                                Divider()
                                Button("Archive") {
                                    store.archive(project)
                                }
                                Button("Delete", role: .destructive) {
                                    store.delete(project)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button { startNewProject() } label: {
                    Label("New Project", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .navigationTitle("FacetX")
        } detail: {
            if let project = selected {
                ProjectDetailView(project: project)
            } else if store.activeProjects.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView("No projects yet",
                        systemImage: "folder",
                        description: Text("Create a project to gather its calendar and reminder items."))
                    Button { startNewProject() } label: {
                        Label("New Project", systemImage: "plus.circle")
                    }
                }
            } else {
                ContentUnavailableView("Select a project",
                    systemImage: "folder",
                    description: Text("Pick a project from the sidebar."))
            }
        }
        .task {
            if !ek.remindersAuthorized && !ek.calendarAuthorized {
                await ek.requestAccess()
            }
            discovered = await ek.discoverProjectNames()
        }
        .sheet(item: $draftProject) { draft in
            NewProjectView(draft: draft) { name, prefix, tagline, reminderList, calendar in
                let id = store.createProject(name: name, prefix: prefix, tagline: tagline,
                                             reminderListName: reminderList, calendarName: calendar)
                selectedID = id
                draftProject = nil
            } onCancel: {
                draftProject = nil
            }
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project) { editingProject = nil }
        }
    }

    private func startNewProject() {
        let existing = Set(store.projects.map(\.name))
        let suggestion = discovered.first { !existing.contains($0) } ?? uniqueProjectName(in: existing)
        let reminderLists = ek.reminderListNames(enabled: settings.enabledContainerNames)
        let calendars = ek.calendarNames(enabled: settings.enabledContainerNames)
        draftProject = ProjectDraft(
            name: suggestion,
            prefix: suggestion,
            reminderListName: defaultName(settings.defaultReminderListName, in: reminderLists),
            calendarName: defaultName(settings.defaultCalendarName, in: calendars),
            reminderLists: reminderLists,
            calendars: calendars
        )
    }

    private func uniqueProjectName(in existing: Set<String>) -> String {
        let base = "New Project"
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func defaultName(_ name: String, in options: [String]) -> String {
        options.contains(name) ? name : (options.first ?? "")
    }
}

/// Detail pane: a project's items, grouped by container (functional zone).
struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    let project: Project

    enum Mode: String, CaseIterable, Identifiable {
        case all = "All", week = "Week"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var showCreate = false
    @State private var editingItem: ProjectItem?
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""

    private var grouped: [(zone: String, items: [ProjectItem])] {
        Dictionary(grouping: items, by: \.containerName)
            .map { ($0.key, $0.value) }
            .sorted { $0.zone < $1.zone }
    }

    var body: some View {
        Group {
            switch mode {
            case .all:  allItemsView
            case .week: WeekView(project: project)
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .help("Add an item to this project")
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateItemView(project: project) { Task { await reload() } }
        }
        .sheet(item: $editingItem) { item in
            EditItemView(project: project, item: item) { Task { await reload() } }
        }
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
    }

    @ViewBuilder private var allItemsView: some View {
        if loading {
            ProgressView().controlSize(.large)
        } else {
            List {
                if items.isEmpty {
                    Section {
                        Text("No items yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(grouped, id: \.zone) { group in
                        Section(group.zone) {
                            ForEach(group.items) { item in
                                ItemRow(
                                    item: item,
                                    onToggle: { completed in
                                        Task {
                                            await ek.setReminderCompleted(id: item.id, completed: completed)
                                            await reload()
                                        }
                                    },
                                    onEdit: {
                                        editingItem = item
                                    },
                                    inlineEditingText: $inlineEditingText,
                                    isInlineEditing: item.id == inlineEditingID,
                                    onInlineCommit: {
                                        commitInlineEdit(for: item)
                                    },
                                    onInlineCancel: {
                                        cancelInlineEdit(for: item)
                                    }
                                )
                                .contextMenu {
                                    Button("Edit...") {
                                        editingItem = item
                                    }
                                    Button("Delete", role: .destructive) {
                                        _ = ek.deleteItem(id: item.id)
                                        Task { await reload() }
                                    }
                                }
                                .onTapGesture(count: 2) {
                                    startInlineEdit(for: item)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button {
                        addNewItemInline()
                    } label: {
                        Label("Add item...", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func startInlineEdit(for item: ProjectItem) {
        inlineEditingText = item.content
        inlineEditingID = item.id
    }

    private func commitInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        let newContent = inlineEditingText.trimmingCharacters(in: .whitespaces)
        inlineEditingID = nil
        
        if newContent.isEmpty {
            _ = ek.deleteItem(id: item.id)
        } else if newContent != item.content {
            _ = ek.updateItem(id: item.id, project: project.prefix, content: newContent,
                               date: item.date, useDate: item.date != nil,
                               containerName: item.containerName)
        }
        Task { await reload() }
    }

    private func cancelInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        inlineEditingID = nil
        if item.content == "新建代办" {
            _ = ek.deleteItem(id: item.id)
        }
        Task { await reload() }
    }

    private func addNewItemInline() {
        let reminderList = project.reminderListName ?? settings.defaultReminderListName
        guard !reminderList.isEmpty else { return }
        Task {
            if let newId = ek.createReminder(project: project.prefix, content: "新建代办",
                                             listName: reminderList, dueDate: nil) {
                await reload()
                startInlineEdit(for: .init(id: newId, kind: .reminder, rawTitle: "", content: "新建代办", containerName: reminderList, isCompleted: false, date: nil))
            }
        }
    }

    private func reload() async {
        loading = items.isEmpty
        items = await ek.items(forProject: project.prefix,
                               enabledContainers: settings.enabledContainerNames)
        loading = false
    }
}

private struct ProjectDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
    var reminderListName: String
    var calendarName: String
    var reminderLists: [String]
    var calendars: [String]
}

private struct NewProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String, String?, String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prefix = State(initialValue: draft.prefix)
        _tagline = State(initialValue: draft.tagline)
        _reminderListName = State(initialValue: draft.reminderListName)
        _calendarName = State(initialValue: draft.calendarName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title2).bold()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Prefix", text: $prefix)
                    Text("Items whose title starts with “\(effectivePrefix):” belong to this project.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("Tagline", text: $tagline)
                    Picker("Reminders", selection: $reminderListName) {
                        if draft.reminderLists.isEmpty { Text("None").tag("") }
                        ForEach(draft.reminderLists, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Calendar", selection: $calendarName) {
                        if draft.calendars.isEmpty { Text("None").tag("") }
                        ForEach(draft.calendars, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || reminderListName.isEmpty || calendarName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedPrefix: String {
        prefix.trimmingCharacters(in: .whitespaces)
    }

    private var effectivePrefix: String {
        trimmedPrefix.isEmpty ? (trimmedName.isEmpty ? "..." : trimmedName) : trimmedPrefix
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces),
                 reminderListName.isEmpty ? nil : reminderListName,
                 calendarName.isEmpty ? nil : calendarName)
    }
}

private struct EditProjectView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let onClose: () -> Void

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var reminderListName = ""
    @State private var calendarName = ""
    @State private var reminderLists: [String] = []
    @State private var calendars: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project").font(.title2).bold()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Prefix", text: $prefix)
                    Text("Items whose title starts with “\(effectivePrefix):” belong to this project.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("Tagline", text: $tagline)
                    Picker("Reminders", selection: $reminderListName) {
                        if reminderLists.isEmpty { Text("None").tag("") }
                        ForEach(reminderLists, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Calendar", selection: $calendarName) {
                        if calendars.isEmpty { Text("None").tag("") }
                        ForEach(calendars, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if project.archived {
                    Button("Unarchive") { unarchive() }
                } else {
                    Button("Archive") { archive() }
                }
                Button("Delete", role: .destructive) { delete() }
                Spacer()
                Button("Cancel", action: onClose)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: loadFields)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedPrefix: String {
        prefix.trimmingCharacters(in: .whitespaces)
    }

    private var effectivePrefix: String {
        trimmedPrefix.isEmpty ? (trimmedName.isEmpty ? "..." : trimmedName) : trimmedPrefix
    }

    private func loadFields() {
        reminderLists = ek.reminderListNames(enabled: settings.enabledContainerNames)
        calendars = ek.calendarNames(enabled: settings.enabledContainerNames)
        name = project.name
        prefix = project.prefix
        tagline = project.tagline
        reminderListName = firstAvailable(project.reminderListName,
                                          settings.defaultReminderListName,
                                          in: reminderLists)
        calendarName = firstAvailable(project.calendarName,
                                      settings.defaultCalendarName,
                                      in: calendars)
    }

    private func save() {
        var updated = project
        updated.name = trimmedName
        updated.prefix = trimmedPrefix.isEmpty ? trimmedName : trimmedPrefix
        updated.tagline = tagline.trimmingCharacters(in: .whitespaces)
        updated.reminderListName = reminderListName.isEmpty ? nil : reminderListName
        updated.calendarName = calendarName.isEmpty ? nil : calendarName
        store.update(updated)
        onClose()
    }

    private func firstAvailable(_ preferred: String?, _ fallback: String, in options: [String]) -> String {
        if let preferred, options.contains(preferred) { return preferred }
        if options.contains(fallback) { return fallback }
        return options.first ?? ""
    }

    private func archive() {
        store.archive(project)
        onClose()
    }

    private func unarchive() {
        var updated = project
        updated.archived = false
        store.update(updated)
        onClose()
    }

    private func delete() {
        store.delete(project)
        onClose()
    }
}

struct InlineEditTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13, weight: .regular)
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
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    
    // Inline editing bindings and parameters (optional)
    let inlineEditingText: Binding<String>?
    let isInlineEditing: Bool
    let onInlineCommit: (() -> Void)?
    let onInlineCancel: (() -> Void)?

    @State private var hovered = false

    init(item: ProjectItem,
         onToggle: @escaping (Bool) -> Void,
         onEdit: @escaping () -> Void,
         inlineEditingText: Binding<String>? = nil,
         isInlineEditing: Bool = false,
         onInlineCommit: (() -> Void)? = nil,
         onInlineCancel: (() -> Void)? = nil) {
        self.item = item
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.inlineEditingText = inlineEditingText
        self.isInlineEditing = isInlineEditing
        self.onInlineCommit = onInlineCommit
        self.onInlineCancel = onInlineCancel
    }

    var body: some View {
        HStack(spacing: 10) {
            if item.kind == .reminder {
                Button { onToggle(!item.isCompleted) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "calendar").foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if isInlineEditing, let inlineEditingText {
                    InlineEditTextField(text: inlineEditingText,
                                        onCommit: { onInlineCommit?() },
                                        onCancel: { onInlineCancel?() })
                        .frame(minHeight: 20)
                } else {
                    Text(item.content)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                }
                
                if let date = item.date {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            
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
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = isHovered
            }
        }
    }
}
