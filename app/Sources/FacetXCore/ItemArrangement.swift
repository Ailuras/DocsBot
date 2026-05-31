import Foundation

/// Pure ordering, grouping and week-filtering for a project's items. Kept free
/// of SwiftUI and EventKit so it can be unit-checked in FacetXCoreChecks — these
/// are the rules most prone to silent regressions.
public enum ItemArrangement {

    /// A zone (container) and the items it holds, for the grouped list view.
    public struct ZoneGroup: Identifiable, Equatable {
        public let zone: String
        public let items: [ProjectItem]
        public var id: String { zone }
        public init(zone: String, items: [ProjectItem]) {
            self.zone = zone
            self.items = items
        }
    }

    /// The all-items order: incomplete before completed, then the project's saved
    /// manual order, then earliest date as a tiebreaker. Undated items sort last.
    public static func arranged(_ items: [ProjectItem], savedOrder: [String]) -> [ProjectItem] {
        // Precompute id → rank so each comparison is O(1) instead of scanning
        // savedOrder, keeping the overall sort at O(n log n).
        var rank = [String: Int](minimumCapacity: savedOrder.count)
        for (i, id) in savedOrder.enumerated() { rank[id] = i }
        return items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            let ra = rank[a.id] ?? Int.max
            let rb = rank[b.id] ?? Int.max
            if ra == rb { return (a.date ?? .distantFuture) < (b.date ?? .distantFuture) }
            return ra < rb
        }
    }

    /// Incomplete before completed, then earliest date. Used by the week view.
    public static func byDate(_ items: [ProjectItem]) -> [ProjectItem] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    /// Group items by container, preserving each item's incoming order within a
    /// group and sorting the groups by zone name. Pass already-arranged items so
    /// the per-group order is meaningful.
    public static func groupedByZone(_ items: [ProjectItem]) -> [ZoneGroup] {
        Dictionary(grouping: items, by: \.containerName)
            .map { ZoneGroup(zone: $0.key, items: $0.value) }
            .sorted { $0.zone < $1.zone }
    }

    /// The subset of items whose date falls within `week`, ordered by date.
    public static func inWeek(_ items: [ProjectItem], _ week: ISOWeek) -> [ProjectItem] {
        byDate(items.filter { item in
            guard let d = item.date else { return false }
            return week.contains(d)
        })
    }
}
