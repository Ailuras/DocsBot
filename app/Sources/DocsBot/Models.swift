import Foundation

/// A declared project. Owns calendar/reminder items by title prefix; the items
/// themselves live in EventKit, not here. This store holds only project-side
/// metadata EventKit cannot represent.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// The title prefix this project claims. Defaults to `name` but is editable
    /// so it need not collide with historical action-type prefixes.
    var prefix: String
    var tagline: String = ""
    var createdAt: Date = Date()
    var archived: Bool = false
    var weekGoals: [WeekGoal] = []

    init(name: String, prefix: String? = nil, tagline: String = "") {
        self.name = name
        self.prefix = prefix ?? name
        self.tagline = tagline
    }
}

/// A per-week goal attached to a project. ISO week id like "2026-W22".
struct WeekGoal: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var weekId: String
    var title: String
    var body: String = ""
}

/// Persists declared projects to a JSON file under Application Support.
/// Small dataset → a plain Codable store beats SwiftData here and keeps the
/// pure-SwiftPM (Command Line Tools) build working.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let url: URL

    init(filename: String = "projects.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocsBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
        load()
    }

    var activeProjects: [Project] {
        projects.filter { !$0.archived }.sorted { $0.createdAt < $1.createdAt }
    }

    func declare(name: String, tagline: String = "") {
        projects.append(Project(name: name, tagline: tagline))
        save()
    }

    func update(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        save()
    }

    func archive(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].archived = true
        save()
    }

    // ── Week goals ────────────────────────────────────────────────────────────

    func weekGoal(projectID: Project.ID, weekId: String) -> WeekGoal? {
        projects.first { $0.id == projectID }?
            .weekGoals.first { $0.weekId == weekId }
    }

    /// Create or update the goal for a project's week. Empty title removes it.
    func setWeekGoal(projectID: Project.ID, weekId: String, title: String, body: String) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let g = projects[p].weekGoals.firstIndex(where: { $0.weekId == weekId }) {
            if trimmed.isEmpty {
                projects[p].weekGoals.remove(at: g)
            } else {
                projects[p].weekGoals[g].title = trimmed
                projects[p].weekGoals[g].body = body
            }
        } else if !trimmed.isEmpty {
            projects[p].weekGoals.append(WeekGoal(weekId: weekId, title: trimmed, body: body))
        }
        save()
    }

    // ── Persistence ──────────────────────────────────────────────────────────

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        projects = (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(projects).write(to: url, options: .atomic)
    }
}
