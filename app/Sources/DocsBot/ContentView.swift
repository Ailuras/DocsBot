import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: Settings

    @State private var selectedID: Project.ID?
    @State private var showDeclareSheet = false
    @State private var showSettings = false

    private var selected: Project? {
        store.activeProjects.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationSplitView {
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
                    }
                }
            }
            .navigationTitle("DocsBot")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .help("Choose calendars and reminder lists")
                    Button { showDeclareSheet = true } label: { Image(systemName: "plus") }
                        .help("Declare a project")
                }
            }
        } detail: {
            if let project = selected {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView("Select a project",
                    systemImage: "folder",
                    description: Text("Declare a project to gather its calendar and reminder items."))
            }
        }
        .sheet(isPresented: $showDeclareSheet) {
            DeclareProjectView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            if !ek.remindersAuthorized && !ek.calendarAuthorized {
                await ek.requestAccess()
            }
        }
    }
}

/// Detail pane: a project's items, grouped by container (functional zone).
struct ProjectDetailView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: Settings
    let project: Project

    enum Mode: String, CaseIterable, Identifiable {
        case all = "All", week = "Week"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .all
    @State private var items: [ProjectItem] = []
    @State private var loading = false
    @State private var showCreate = false

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
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
    }

    @ViewBuilder private var allItemsView: some View {
        if loading {
            ProgressView().controlSize(.large)
        } else if items.isEmpty {
            ContentUnavailableView("No items",
                systemImage: "tray",
                description: Text("No calendar or reminder items start with “\(project.prefix):”."))
        } else {
            List {
                ForEach(grouped, id: \.zone) { group in
                    Section(group.zone) {
                        ForEach(group.items) { item in
                            ItemRow(item: item) { completed in
                                Task {
                                    await ek.setReminderCompleted(id: item.id, completed: completed)
                                    await reload()
                                }
                            }
                        }
                    }
                }
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

struct ItemRow: View {
    let item: ProjectItem
    let onToggle: (Bool) -> Void

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
                Text(item.content)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                if let date = item.date {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
