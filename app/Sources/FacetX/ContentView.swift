import SwiftUI
import UniformTypeIdentifiers

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
                            ProjectSidebarRow(project: project)
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
                .listStyle(.sidebar)
                Divider()
                Button { startNewProject() } label: {
                    Label("New Project", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.82))
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
        .navigationSplitViewStyle(.balanced)
        .task {
            if !ek.remindersAuthorized && !ek.calendarAuthorized {
                await ek.requestAccess()
            }
            discovered = await ek.discoverProjectNames(
                enabledReminderLists: settings.enabledReminderListNames,
                enabledCalendars: settings.enabledCalendarNames
            )
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
        let reminderLists = ek.reminderListNames(enabled: settings.enabledReminderListNames)
        let calendars = ek.calendarNames(enabled: settings.enabledCalendarNames)
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

private struct ProjectSidebarRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(project.tagline.isEmpty ? project.prefix : project.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var initial: String {
        project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "F"
    }
}

/// Detail pane: a project's items, grouped by container (functional zone).
struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
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
    @State private var inlineEditingID: String?
    @State private var inlineEditingText: String = ""
    @State private var inlineEditingNotesID: String?
    @State private var inlineEditingNotesText: String = ""
    @State private var draggedItem: ProjectItem? = nil
    @State private var selectedDetailItem: ProjectItem? = nil
    @State private var showCompleted = true
    /// The id of an item just created by "Add item" and still showing its
    /// placeholder text. Tracked by id (not by matching the placeholder string)
    /// so cancelling its edit removes exactly that row and nothing else.
    @State private var freshlyCreatedID: String?

    private static let placeholderContent = "新建代办"

    private var listAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var visibleItems: [ProjectItem] {
        showCompleted ? items : items.filter { !$0.isCompleted }
    }

    private var grouped: [(zone: String, items: [ProjectItem])] {
        // Dictionary(grouping:) preserves each item's order within its group, and
        // visibleItems is already sorted, so the group arrays need no re-sort.
        Dictionary(grouping: visibleItems, by: \.containerName)
            .map { (zone: $0.key, items: $0.value) }
            .sorted { $0.zone < $1.zone }
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch mode {
                case .all:  allItemsView
                case .week: WeekView(project: project, selectedItem: $selectedDetailItem)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let selectedItem = selectedDetailItem {
                Divider()
                ItemDetailPane(item: selectedItem, project: project, onClose: {
                    selectedDetailItem = nil
                }, onUpdate: {
                    Task { await reload() }
                })
                .frame(width: 340)
                .transition(.move(edge: .trailing))
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
                Button {
                    withAnimation(listAnimation) {
                        showCompleted.toggle()
                    }
                } label: {
                    Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(showCompleted ? "Hide completed reminders" : "Show completed reminders")
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .help("Add an item to this project")
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateItemView(project: project) { Task { await reload() } }
        }
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: showCompleted) {
            if !showCompleted, selectedDetailItem?.isCompleted == true {
                withAnimation(listAnimation) {
                    selectedDetailItem = nil
                }
            }
        }
    }

    @ViewBuilder private var allItemsView: some View {
        VStack(spacing: 0) {
            projectHeader

            if loading {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            } else {
                allItemsList
            }
        }
        .background(FacetTheme.canvas)
    }

    private var allItemsList: some View {
        List {
            if visibleItems.isEmpty {
                Section {
                    Text(items.isEmpty ? "No items yet." : "Completed items are hidden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(grouped, id: \.zone) { group in
                    Section {
                        ForEach(group.items) { item in
                            projectItemRow(item)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.98))
                                ))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                        }
                    } header: {
                        Text(group.zone)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.top, 4)
                    }
                }
            }

            Section {
                Button {
                    addNewItemInline()
                } label: {
                    Label("Add item...", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 12, trailing: 16))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(listAnimation, value: visibleItems.map { "\($0.id)-\($0.isCompleted)" })
    }

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                HStack(spacing: 8) {
                    if !project.tagline.isEmpty {
                        Text(project.tagline)
                    }
                    Text("#\(project.prefix)")
                        .monospaced()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                summaryChip(value: openItemCount, label: "Open", systemImage: "circle")
                summaryChip(value: completedReminderCount, label: "Done", systemImage: "checkmark.circle")
                summaryChip(value: zoneCount, label: "Zones", systemImage: "square.grid.2x2")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var openItemCount: Int {
        items.filter { $0.kind == .event || !$0.isCompleted }.count
    }

    private var completedReminderCount: Int {
        items.filter { $0.kind == .reminder && $0.isCompleted }.count
    }

    private var zoneCount: Int {
        Set(items.map(\.containerName)).count
    }

    private func summaryChip(value: Int, label: String, systemImage: String) -> some View {
        Label {
            Text("\(value) \(label)")
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FacetTheme.quietPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func projectItemRow(_ item: ProjectItem) -> some View {
        ItemRow(
            item: item,
            isSelected: item.id == selectedDetailItem?.id,
            onToggle: { completed in
                Task {
                    await ek.setReminderCompleted(id: item.id, completed: completed)
                    await reload()
                }
            },
            onEdit: {
                withAnimation(.easeOut(duration: 0.15)) { selectedDetailItem = item }
            },
            inlineEditingText: $inlineEditingText,
            isInlineEditing: item.id == inlineEditingID,
            onInlineCommit: {
                commitInlineEdit(for: item)
            },
            onInlineCancel: {
                cancelInlineEdit(for: item)
            },
            inlineEditingNotesText: $inlineEditingNotesText,
            isInlineEditingNotes: item.id == inlineEditingNotesID,
            onInlineNotesCommit: {
                commitInlineNotesEdit(for: item)
            },
            onInlineNotesCancel: {
                cancelInlineNotesEdit(for: item)
            },
            onStartNotesEdit: {
                startInlineNotesEdit(for: item)
            }
        )
        .contextMenu {
            Button("Edit...") {
                withAnimation(.easeOut(duration: 0.15)) { selectedDetailItem = item }
            }
            Button("Delete", role: .destructive) {
                Task { _ = await ek.deleteItem(id: item.id); await reload() }
            }
        }
        .onTapGesture(count: 2) {
            startInlineEdit(for: item)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDetailItem = item
            }
        }
        .onDrag {
            self.draggedItem = item
            return NSItemProvider(object: item.id as NSString)
        }
        .onDrop(of: [.text], delegate: ItemDropDelegate(
            item: item,
            draggedItem: $draggedItem,
            onMove: { dragged, target in moveItem(from: dragged, to: target) },
            onDrop: { commitItemOrder() }
        ))
    }

    private func startInlineEdit(for item: ProjectItem) {
        inlineEditingText = item.content
        inlineEditingID = item.id
    }

    private func commitInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        let newContent = inlineEditingText.trimmingCharacters(in: .whitespaces)
        inlineEditingID = nil
        freshlyCreatedID = nil

        Task {
            if newContent.isEmpty {
                _ = await ek.deleteItem(id: item.id)
            } else if newContent != item.content {
                _ = await ek.updateItem(id: item.id, project: project.prefix, content: newContent,
                                        date: item.date, useDate: item.date != nil,
                                        containerName: item.containerName, notes: item.notes,
                                        priority: item.priority)
            }
            await reload()
        }
    }

    private func cancelInlineEdit(for item: ProjectItem) {
        guard inlineEditingID == item.id else { return }
        inlineEditingID = nil
        // Only discard the row if it was a never-filled fresh placeholder.
        let wasFresh = freshlyCreatedID == item.id
        freshlyCreatedID = nil
        Task {
            if wasFresh { _ = await ek.deleteItem(id: item.id) }
            await reload()
        }
    }

    private func startInlineNotesEdit(for item: ProjectItem) {
        inlineEditingNotesText = item.notes ?? ""
        inlineEditingNotesID = item.id
    }

    private func commitInlineNotesEdit(for item: ProjectItem) {
        guard inlineEditingNotesID == item.id else { return }
        let newNotes = inlineEditingNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        inlineEditingNotesID = nil
        
        let notesParam = newNotes.isEmpty ? nil : newNotes
        Task {
            if notesParam != item.notes {
                _ = await ek.updateItem(id: item.id, project: project.prefix, content: item.content,
                                        date: item.date, useDate: item.date != nil,
                                        containerName: item.containerName, notes: notesParam,
                                        priority: item.priority)
            }
            await reload()
        }
    }

    private func cancelInlineNotesEdit(for item: ProjectItem) {
        guard inlineEditingNotesID == item.id else { return }
        inlineEditingNotesID = nil
        Task { await reload() }
    }

    private func addNewItemInline() {
        let reminderList = project.reminderListName ?? settings.defaultReminderListName
        guard !reminderList.isEmpty else { return }
        Task {
            if let newId = await ek.createReminder(project: project.prefix, content: Self.placeholderContent,
                                                   listName: reminderList, dueDate: nil) {
                freshlyCreatedID = newId
                await reload()
                startInlineEdit(for: .init(id: newId, kind: .reminder, rawTitle: "", content: Self.placeholderContent, containerName: reminderList, isCompleted: false, date: nil, notes: nil, priority: 0, url: nil))
            }
        }
    }

    private func reload() async {
        loading = items.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.enabledReminderListNames,
                                     enabledCalendars: settings.enabledCalendarNames)
        store.pruneItemOrder(projectID: project.id, keeping: Set(fetched.map(\.id)))
        let sortedItems = sortItems(fetched)
        let selectedId = selectedDetailItem?.id
        if items.isEmpty {
            items = sortedItems
            if let selectedId {
                selectedDetailItem = visibleItems.first { $0.id == selectedId }
            }
        } else {
            withAnimation(listAnimation) {
                items = sortedItems
                if let selectedId {
                    selectedDetailItem = visibleItems.first { $0.id == selectedId }
                }
            }
        }
        loading = false
    }

    private func sortItems(_ fetched: [ProjectItem]) -> [ProjectItem] {
        let order = project.itemOrder ?? []
        return fetched.sorted { a, b in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted
            }
            let indexA = order.firstIndex(of: a.id) ?? Int.max
            let indexB = order.firstIndex(of: b.id) ?? Int.max
            if indexA == indexB {
                return (a.date ?? Date.distantFuture) < (b.date ?? Date.distantFuture)
            }
            return indexA < indexB
        }
    }

    private func moveItem(from source: ProjectItem, to destination: ProjectItem) {
        guard let fromIndex = items.firstIndex(where: { $0.id == source.id }),
              let toIndex = items.firstIndex(where: { $0.id == destination.id }) else {
            return
        }
        
        if fromIndex != toIndex {
            withAnimation(.default) {
                let movedItem = items.remove(at: fromIndex)
                items.insert(movedItem, at: toIndex)
            }
        }
    }

    /// Persist the current in-memory item order. Called once when the drag is
    /// released, not on every drag-over (which would write to disk repeatedly).
    private func commitItemOrder() {
        store.setItemOrder(projectID: project.id, orderedIDs: items.map(\.id))
    }
}
