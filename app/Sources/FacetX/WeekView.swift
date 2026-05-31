import FacetXCore
import SwiftUI

/// Single-project week view: a time-focused slice — this week's goal plus the
/// project's items whose due/start date falls within the selected ISO week.
struct WeekView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    /// The item shown in the shared detail pane (owned by ProjectDetailView), so
    /// week-view edits open the same side pane as the all-items view.
    @Binding var selectedItem: ProjectItem?

    @State private var week = ISOWeek.containing(Date())
    @State private var allItems: [ProjectItem] = []
    @State private var loading = false
    @State private var editingGoal = false
    @State private var goalTitle = ""
    @State private var goalBody = ""

    private var listAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var weekItems: [ProjectItem] {
        allItems.filter { item in
            guard let d = item.date else { return false }
            return week.contains(d)
        }
        .sorted { a, b in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted
            }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    private var goal: WeekGoal? {
        store.weekGoal(projectID: project.id, weekId: week.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekNav
            VStack(alignment: .leading, spacing: 14) {
                goalSection
                itemsSection
                Spacer()
            }
            .padding(16)
        }
        .background(FacetTheme.canvas)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
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
            .padding(12)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
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
            .padding(12)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        } else {
            Button { startEditingGoal() } label: {
                Label("Set this week's goal", systemImage: "plus.circle")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
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
                ItemRow(item: item, isSelected: item.id == selectedItem?.id) { completed in
                    Task {
                        await ek.setReminderCompleted(id: item.id, completed: completed)
                        await reload()
                    }
                } onEdit: {
                    selectItem(item)
                }
                .contextMenu {
                    Button("Edit...") {
                        selectItem(item)
                    }
                    Button("Delete", role: .destructive) {
                        Task { _ = await ek.deleteItem(id: item.id); await reload() }
                    }
                }
                .onTapGesture {
                    selectItem(item)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: weekItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    private func selectItem(_ item: ProjectItem) {
        withAnimation(.easeOut(duration: 0.15)) { selectedItem = item }
    }

    private func startEditingGoal() {
        goalTitle = goal?.title ?? ""
        goalBody = goal?.body ?? ""
        editingGoal = true
    }

    private func reload() async {
        loading = allItems.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.enabledReminderListNames,
                                     enabledCalendars: settings.enabledCalendarNames)
        if allItems.isEmpty {
            allItems = fetched
        } else {
            withAnimation(listAnimation) {
                allItems = fetched
            }
        }
        loading = false
    }
}
