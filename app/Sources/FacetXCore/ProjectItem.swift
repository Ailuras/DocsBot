import Foundation

/// A reminder or calendar event, flattened for the UI and tagged with the
/// project it belongs to (via the title prefix).
///
/// Lives in FacetXCore — free of EventKit/SwiftUI — so the pure ordering and
/// grouping logic in `ItemArrangement` can be unit-checked. `EventKitService`
/// builds these value types from EKReminder/EKEvent inside its fetch callbacks.
public struct ProjectItem: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case reminder, event }
    public let id: String          // EventKit calendarItemIdentifier / eventIdentifier
    public let kind: Kind
    public let rawTitle: String
    public let content: String     // title with the project prefix stripped
    public let containerName: String   // reminder list / calendar = functional zone
    public let isCompleted: Bool
    public let date: Date?         // due date (reminder) or start date (event)
    public let notes: String?      // notes / description
    public let priority: Int       // priority value (0 = none, 1-4 = high, 5 = med, 9 = low)
    public let url: URL?           // URL associated with the item

    public init(id: String, kind: Kind, rawTitle: String, content: String,
                containerName: String, isCompleted: Bool, date: Date?,
                notes: String?, priority: Int, url: URL?) {
        self.id = id
        self.kind = kind
        self.rawTitle = rawTitle
        self.content = content
        self.containerName = containerName
        self.isCompleted = isCompleted
        self.date = date
        self.notes = notes
        self.priority = priority
        self.url = url
    }
}
