import FacetXCore
import SwiftUI

/// Cross-project Today view: a single place to see everything due today or
/// overdue across all projects, instead of opening each project in turn.
/// Reads straight from EventKit (no new storage) and tags each row with its
/// owning project.
struct TodayView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    /// Jump to a project in the sidebar when a row is tapped.
    let onOpenProject: (Project.ID) -> Void

    @State private var items: [ProjectItem] = []
    @State private var loading = false

    private var listAnimation: Animation { .spring(response: 0.34, dampingFraction: 0.88) }

    /// Map a claimed prefix to its project, for the row badge and tap target.
    private var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    private var overdue: [ProjectItem] { items.filter { bucket(for: $0) == .overdue } }
    private var today: [ProjectItem] { items.filter { bucket(for: $0) == .today } }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(FacetTheme.canvas)
        .task { await reload() }
        .onChange(of: ek.changeToken) { Task { await reload() } }
    }

    @ViewBuilder private var content: some View {
        if overdue.isEmpty && today.isEmpty {
            ContentUnavailableView {
                Label("All clear", systemImage: "checkmark.circle")
            } description: {
                Text(store.activeProjects.isEmpty
                     ? "Create a project to start gathering its items here."
                     : "Nothing is due today across your projects.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if loading && items.isEmpty { ProgressView().controlSize(.large) }
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            section(title: "Overdue", tint: .red, rows: overdue)
            section(title: "Today", tint: .accentColor, rows: today)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(listAnimation, value: items.map { "\($0.id)-\($0.isCompleted)" })
    }

    @ViewBuilder
    private func section(title: String, tint: Color, rows: [ProjectItem]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { item in row(item) }
            } header: {
                HStack(spacing: 6) {
                    Text(title)
                    Text("\(rows.count)")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint == .red ? .red : .secondary)
                .textCase(nil)
                .padding(.top, 4)
            }
        }
    }

    private func row(_ item: ProjectItem) -> some View {
        let project = projectsByPrefix[ProjectPrefix.projectName(of: item.rawTitle) ?? ""]
        return ItemRow(
            item: item,
            projectBadge: project?.name ?? ProjectPrefix.projectName(of: item.rawTitle),
            onToggle: { completed in
                Task {
                    await ek.setReminderCompleted(id: item.id, completed: completed)
                    await reload()
                }
            },
            onEdit: { if let project { onOpenProject(project.id) } }
        )
        .contentShape(Rectangle())
        .onTapGesture { if let project { onOpenProject(project.id) } }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 18, weight: .semibold))
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                summaryChip(value: overdue.count, label: "Overdue", systemImage: "exclamationmark.circle")
                summaryChip(value: today.count, label: "Today", systemImage: "sun.max")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private func summaryChip(value: Int, label: String, systemImage: String) -> some View {
        Label("\(value) \(label)", systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(FacetTheme.quietPanel))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(FacetTheme.hairline, lineWidth: 1))
    }

    // ── Classification ───────────────────────────────────────────────────────

    private enum Bucket { case overdue, today }

    /// Today shows actionable, dated items: today's reminders/events, plus
    /// still-open overdue reminders. Completed reminders and past events drop out.
    private func bucket(for item: ProjectItem) -> Bucket? {
        guard let date = item.date else { return nil }
        if item.kind == .reminder && item.isCompleted { return nil }
        if Calendar.current.isDateInToday(date) { return .today }
        if date < Calendar.current.startOfDay(for: Date()) {
            return item.kind == .reminder ? .overdue : nil
        }
        return nil
    }

    private func reload() async {
        loading = items.isEmpty
        let prefixes = Set(store.activeProjects.map(\.prefix))
        let fetched = await ek.items(forProjects: prefixes,
                                     enabledReminderLists: settings.enabledReminderListNames,
                                     enabledCalendars: settings.enabledCalendarNames)
        let sorted = fetched.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        if items.isEmpty {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { items = sorted }
        } else {
            withAnimation(listAnimation) { items = sorted }
        }
        loading = false
    }
}
