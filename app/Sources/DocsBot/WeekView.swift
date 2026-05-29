import SwiftUI

/// Single-project week view: a time-focused slice — this week's goal plus the
/// project's items whose due/start date falls within the selected ISO week.
struct WeekView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: Settings

    let project: Project

    @State private var week = ISOWeek.containing(Date())
    @State private var allItems: [ProjectItem] = []
    @State private var loading = false
    @State private var editingGoal = false
    @State private var goalTitle = ""
    @State private var goalBody = ""

    private var weekItems: [ProjectItem] {
        allItems.filter { item in
            guard let d = item.date else { return false }
            return week.contains(d)
        }
    }

    private var goal: WeekGoal? {
        store.weekGoal(projectID: project.id, weekId: week.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            weekNav
            goalSection
            Divider()
            itemsSection
            Spacer()
        }
        .padding(16)
        .task(id: project.id) { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
    }

    // ── Week navigation ──────────────────────────────────────────────────────
    private var weekNav: some View {
        HStack {
            Button { week = week.shifted(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(week.label).font(.headline)
                Text(week.id).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { week = week.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
            Button("This week") { week = ISOWeek.containing(Date()) }
                .font(.caption)
        }
    }

    // ── Goal ─────────────────────────────────────────────────────────────────
    @ViewBuilder private var goalSection: some View {
        if editingGoal {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weekly goal").font(.caption).foregroundStyle(.secondary)
                TextField("This week I'm focused on…", text: $goalTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Details (optional)", text: $goalBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                HStack {
                    Button("Save") {
                        store.setWeekGoal(projectID: project.id, weekId: week.id,
                                          title: goalTitle, body: goalBody)
                        editingGoal = false
                    }
                    Button("Cancel") { editingGoal = false }
                }
            }
        } else if let goal {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Weekly goal", systemImage: "target")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { startEditingGoal() }.font(.caption)
                }
                Text(goal.title).font(.title3).bold()
                if !goal.body.isEmpty {
                    Text(goal.body).font(.callout).foregroundStyle(.secondary)
                }
            }
        } else {
            Button { startEditingGoal() } label: {
                Label("Set this week's goal", systemImage: "plus.circle")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    // ── Items in this week ───────────────────────────────────────────────────
    @ViewBuilder private var itemsSection: some View {
        Text("Items this week").font(.caption).foregroundStyle(.secondary)
        if loading {
            ProgressView()
        } else if weekItems.isEmpty {
            Text("No dated items fall in this week.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            List(weekItems) { item in
                ItemRow(item: item) { completed in
                    Task {
                        await ek.setReminderCompleted(id: item.id, completed: completed)
                        await reload()
                    }
                }
            }
        }
    }

    private func startEditingGoal() {
        goalTitle = goal?.title ?? ""
        goalBody = goal?.body ?? ""
        editingGoal = true
    }

    private func reload() async {
        loading = allItems.isEmpty
        allItems = await ek.items(forProject: project.prefix,
                                  enabledContainers: settings.enabledContainerNames)
        loading = false
    }
}
