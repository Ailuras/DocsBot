import EventKit
import FacetXCore
import Foundation

/// A reminder or calendar event, flattened for the UI and tagged with the
/// project it belongs to (via the title prefix).
struct ProjectItem: Identifiable, Hashable {
    enum Kind { case reminder, event }
    let id: String          // EventKit calendarItemIdentifier / eventIdentifier
    let kind: Kind
    let rawTitle: String
    let content: String     // title with the project prefix stripped
    let containerName: String   // reminder list / calendar = functional zone
    let isCompleted: Bool
    let date: Date?         // due date (reminder) or start date (event)
    let notes: String?      // notes / description
    let priority: Int       // priority value (0 = none, 1-4 = high, 5 = med, 9 = low)
    let url: URL?           // URL associated with the item
}

/// Wraps EKEventStore: authorization, fetching, prefix-filtering, write-back.
///
/// NOT `@MainActor`: EventKit's fetch callbacks fire on its own background
/// queue, and EKEventStore is not Sendable, so a main-actor-isolated wrapper
/// triggers Swift 6 isolation assertions (SIGTRAP) and data-race diagnostics.
/// Instead the class is nonisolated; only the @Published auth flags are written
/// back on the main actor.
final class EventKitService: ObservableObject, @unchecked Sendable {
    private let store = EKEventStore()

    @Published var remindersAuthorized = false
    @Published var calendarAuthorized = false
    /// Bumped whenever EventKit's data changes (here, in Apple's apps, or via
    /// iCloud). Views observe this to refresh live, Fantastical-style.
    @Published var changeToken = 0

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.changeToken &+= 1
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func requestAccess() async {
        let reminders = (try? await store.requestFullAccessToReminders()) ?? false
        let calendar = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            self.remindersAuthorized = reminders
            self.calendarAuthorized = calendar
        }
    }

    /// Filter a container list by enabled titles. `enabled` empty/nil = all.
    private func filtered(_ calendars: [EKCalendar], by enabled: Set<String>?) -> [EKCalendar] {
        guard let enabled, !enabled.isEmpty else { return calendars }
        return calendars.filter { enabled.contains($0.title) }
    }

    /// All items (reminders + events) whose title prefix matches `project`,
    /// limited to the enabled containers (empty/nil = all).
    func items(forProject project: String,
               enabledReminderLists: Set<String>? = nil,
               enabledCalendars: Set<String>? = nil,
               eventWindowDays: Int = 120) async -> [ProjectItem] {
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var result: [ProjectItem] = []
        if rem { result += await reminders(forProject: project, enabled: enabledReminderLists) }
        if cal { result += events(forProject: project, enabled: enabledCalendars, windowDays: eventWindowDays) }
        return result.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Distinct project names discovered across enabled reminders + recent events.
    func discoverProjectNames(enabledReminderLists: Set<String>? = nil,
                              enabledCalendars: Set<String>? = nil,
                              eventWindowDays: Int = 120) async -> [String] {
        let (rem, cal) = await MainActor.run { (remindersAuthorized, calendarAuthorized) }
        var names = Set<String>()
        if rem {
            // Map to project names inside the callback; EKReminder is not Sendable.
            let discovered = await fetchReminderProjectNames(enabled: enabledReminderLists)
            names.formUnion(discovered)
        }
        if cal {
            for e in recentEvents(enabled: enabledCalendars, windowDays: eventWindowDays) {
                if let n = ProjectPrefix.projectName(of: e.title ?? "") { names.insert(n) }
            }
        }
        return names.sorted()
    }

    // ── Reminders ──────────────────────────────────────────────────────────

    /// Fetch reminders and flatten matching ones to Sendable ProjectItems inside
    /// the EventKit callback, so no non-Sendable EKReminder crosses an actor hop.
    ///
    /// The class is nonisolated, so fetchReminders' background-queue callback can
    /// run freely without tripping the Swift 6 main-actor isolation assertion
    /// (dispatch_assert_queue_fail → SIGTRAP) that crashed an earlier build.
    private func reminders(forProject project: String, enabled: Set<String>?) async -> [ProjectItem] {
        let lists = filtered(store.calendars(for: .reminder), by: enabled)
        guard !lists.isEmpty else { return [] }
        let pred = store.predicateForReminders(in: lists)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { reminders in
                let items = (reminders ?? []).compactMap { r -> ProjectItem? in
                    let title = r.title ?? ""
                    guard ProjectPrefix.belongs(title: title, toProject: project) else { return nil }
                    return ProjectItem(
                        id: r.calendarItemIdentifier,
                        kind: .reminder,
                        rawTitle: title,
                        content: ProjectPrefix.contentBody(of: title),
                        containerName: r.calendar?.title ?? "?",
                        isCompleted: r.isCompleted,
                        date: r.dueDateComponents?.date,
                        notes: r.notes,
                        priority: r.priority,
                        url: r.url
                    )
                }
                cont.resume(returning: items)
            }
        }
    }

    private func fetchReminderProjectNames(enabled: Set<String>?) async -> Set<String> {
        let lists = filtered(store.calendars(for: .reminder), by: enabled)
        guard !lists.isEmpty else { return [] }
        let pred = store.predicateForReminders(in: lists)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { reminders in
                var names = Set<String>()
                for r in reminders ?? [] {
                    if let n = ProjectPrefix.projectName(of: r.title ?? "") { names.insert(n) }
                }
                cont.resume(returning: names)
            }
        }
    }

    // ── Events ─────────────────────────────────────────────────────────────

    private func events(forProject project: String, enabled: Set<String>?, windowDays: Int) -> [ProjectItem] {
        recentEvents(enabled: enabled, windowDays: windowDays).compactMap { e in
            let title = e.title ?? ""
            guard ProjectPrefix.belongs(title: title, toProject: project) else { return nil }
            return ProjectItem(
                id: e.eventIdentifier ?? UUID().uuidString,
                kind: .event,
                rawTitle: title,
                content: ProjectPrefix.contentBody(of: title),
                containerName: e.calendar.title,
                isCompleted: false,
                date: e.startDate,
                notes: e.notes,
                priority: 0,
                url: e.url
            )
        }
    }

    private func recentEvents(enabled: Set<String>?, windowDays: Int) -> [EKEvent] {
        let cals = filtered(store.calendars(for: .event), by: enabled)
        guard !cals.isEmpty else { return [] }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -windowDays, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: windowDays, to: now)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: pred)
    }

    // ── Containers (functional zones) ────────────────────────────────────────

    /// Names of reminder lists, optionally limited to enabled ones.
    func reminderListNames(enabled: Set<String>? = nil) -> [String] {
        filtered(store.calendars(for: .reminder), by: enabled).map(\.title).sorted()
    }

    /// Names of calendars, optionally limited to enabled ones.
    func calendarNames(enabled: Set<String>? = nil) -> [String] {
        filtered(store.calendars(for: .event), by: enabled).map(\.title).sorted()
    }

    /// A container as shown in Settings: its title, kind, and owning account.
    struct ContainerInfo: Identifiable, Hashable {
        enum Kind: String { case calendar = "Calendar", reminder = "Reminders" }
        var id: String { "\(kind.rawValue)/\(sourceTitle)/\(title)" }
        let title: String
        let kind: Kind
        let sourceTitle: String
    }

    /// All containers (calendars + reminder lists) for the Settings list,
    /// grouped-friendly with their owning account title.
    func allContainers() -> [ContainerInfo] {
        var result: [ContainerInfo] = []
        for c in store.calendars(for: .event) {
            result.append(.init(title: c.title, kind: .calendar, sourceTitle: c.source.title))
        }
        for c in store.calendars(for: .reminder) {
            result.append(.init(title: c.title, kind: .reminder, sourceTitle: c.source.title))
        }
        return result
    }

    /// Delete a container (calendar or reminder list) by title. Returns true if
    /// one was removed. Use with care — deletes the list and its contents.
    @discardableResult
    func deleteContainer(title: String, kind: ContainerInfo.Kind) -> Bool {
        let entity: EKEntityType = (kind == .reminder) ? .reminder : .event
        guard let cal = store.calendars(for: entity).first(where: { $0.title == title })
        else { return false }
        do { try store.removeCalendar(cal, commit: true); return true } catch { return false }
    }

    /// Account (source) titles that can hold a NEW container of the given kind.
    /// Not every source allows new lists (e.g. subscribed/birthday sources).
    func sourceTitles(forNew kind: ContainerInfo.Kind) -> [String] {
        let entity: EKEntityType = (kind == .reminder) ? .reminder : .event
        return store.sources
            .filter { src in
                // A source can host new containers of a kind if it already
                // exposes calendars for that entity (filters out read-only ones).
                !src.calendars(for: entity).isEmpty || src.sourceType == .local || src.sourceType == .calDAV
            }
            .map(\.title)
            // De-dup: iCloud may appear as separate calendar/reminder sources.
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted()
    }

    /// Create a new calendar or reminder list named `title` under the account
    /// whose title is `sourceTitle`. Returns true on success.
    @discardableResult
    func createContainer(title: String, kind: ContainerInfo.Kind, sourceTitle: String) -> Bool {
        createContainerResult(title: title, kind: kind, sourceTitle: sourceTitle).ok
    }

    /// Same as createContainer but surfaces the error message for diagnostics.
    func createContainerResult(title: String, kind: ContainerInfo.Kind,
                               sourceTitle: String) -> (ok: Bool, error: String?) {
        let entity: EKEntityType = (kind == .reminder) ? .reminder : .event
        // Prefer a source that actually hosts containers of this entity.
        let source = store.sources.first(where: {
            $0.title == sourceTitle && !$0.calendars(for: entity).isEmpty
        }) ?? store.sources.first(where: { $0.title == sourceTitle })
        guard let source else { return (false, "no source titled \(sourceTitle)") }
        let cal = EKCalendar(for: entity, eventStore: store)
        cal.title = title
        cal.source = source
        do { try store.saveCalendar(cal, commit: true); return (true, nil) }
        catch { return (false, "\(error)") }
    }

    // ── Write-back ───────────────────────────────────────────────────────────

    /// Toggle a reminder's completion by its identifier.
    func setReminderCompleted(id: String, completed: Bool) async {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        item.isCompleted = completed
        try? store.save(item, commit: true)
    }

    /// Create a reminder titled `Project: content` in the named list.
    /// `dueDate` is optional. Returns the reminder's identifier on success, or nil.
    @discardableResult
    func createReminder(project: String, content: String,
                        listName: String, dueDate: Date?, notes: String? = nil, priority: Int = 0) -> String? {
        guard let list = store.calendars(for: .reminder)
            .first(where: { $0.title == listName }) ?? store.defaultCalendarForNewReminders()
        else { return nil }
        let r = EKReminder(eventStore: store)
        r.title = ProjectPrefix.makeTitle(project: project, content: content)
        r.calendar = list
        r.notes = notes
        r.priority = priority
        if let due = dueDate {
            r.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: due)
        }
        do {
            try store.save(r, commit: true)
            return r.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Create a calendar event titled `Project: content` in the named calendar
    /// (= functional zone). Defaults to a 1-hour block at `startDate`.
    @discardableResult
    func createEvent(project: String, content: String,
                     calendarName: String, startDate: Date,
                     durationMinutes: Int = 60, notes: String? = nil) -> Bool {
        guard let cal = store.calendars(for: .event)
            .first(where: { $0.title == calendarName })
        else { return false }
        let e = EKEvent(eventStore: store)
        e.title = ProjectPrefix.makeTitle(project: project, content: content)
        e.calendar = cal
        e.notes = notes
        e.startDate = startDate
        e.endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate)
        do { try store.save(e, span: .thisEvent, commit: true); return true } catch { return false }
    }

    /// Delete an existing calendar item (reminder or event) by its identifier.
    func deleteItem(id: String) -> Bool {
        guard let item = store.calendarItem(withIdentifier: id) else { return false }
        if let reminder = item as? EKReminder {
            do { try store.remove(reminder, commit: true); return true } catch { return false }
        } else if let event = item as? EKEvent {
            do { try store.remove(event, span: .thisEvent, commit: true); return true } catch { return false }
        }
        return false
    }

    /// Update an existing item (reminder or event)'s content, date, container, notes, and priority.
    ///
    /// `url` is only written when `updateURL` is true. Callers that don't edit the
    /// URL (inline title/notes edits, the edit sheet) leave it untouched — passing
    /// the default would otherwise silently erase an item's existing link.
    func updateItem(id: String, project: String, content: String,
                    date: Date?, useDate: Bool, containerName: String, notes: String?, priority: Int,
                    url: URL? = nil, updateURL: Bool = false) -> Bool {
        guard let item = store.calendarItem(withIdentifier: id) else { return false }

        let newTitle = ProjectPrefix.makeTitle(project: project, content: content)
        item.title = newTitle
        item.notes = notes
        if updateURL { item.url = url }

        if let reminder = item as? EKReminder {
            reminder.priority = priority
        }
        
        // Update container if it changed
        if item.calendar?.title != containerName {
            let entity: EKEntityType = (item is EKReminder) ? .reminder : .event
            if let newCal = store.calendars(for: entity).first(where: { $0.title == containerName }) {
                item.calendar = newCal
            }
        }
        
        if let reminder = item as? EKReminder {
            if useDate, let due = date {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
            } else {
                reminder.dueDateComponents = nil
            }
            do { try store.save(reminder, commit: true); return true } catch { return false }
        } else if let event = item as? EKEvent {
            guard let start = date else { return false }
            // Preserve the event's existing duration instead of forcing 1 hour;
            // ProjectItem only carries the start, so the end must be derived.
            let duration = event.endDate.timeIntervalSince(event.startDate)
            event.startDate = start
            event.endDate = start.addingTimeInterval(duration > 0 ? duration : 3600)
            do { try store.save(event, span: .thisEvent, commit: true); return true } catch { return false }
        }
        return false
    }
}
