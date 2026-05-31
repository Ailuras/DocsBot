import FacetXCore
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

check(ProjectPrefix.projectName(of: "Regulus: fix bug") == "Regulus",
      "ASCII colon prefix should parse")
check(ProjectPrefix.projectName(of: "Regulus：fix bug") == "Regulus",
      "Fullwidth colon prefix should parse")
check(ProjectPrefix.projectName(of: "Regulus: first\nOther: second") == "Regulus",
      "Prefix parser should only inspect first line")
check(ProjectPrefix.belongs(title: "Regulus: first\nOther: second", toProject: "Regulus"),
      "belongs should match first-line project prefix")
check(ProjectPrefix.contentBody(of: "Regulus： fix bug") == "fix bug",
      "contentBody should strip colon-tolerant prefix")
check(ProjectPrefix.makeTitle(project: "Regulus", content: "fix bug") == "Regulus: fix bug",
      "makeTitle should write ASCII colon")

let week = ISOWeek(year: 2026, week: 22)
let calendar = Calendar(identifier: .iso8601)
guard let monday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25)),
      let sunday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23)),
      let nextMonday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)) else {
    fatalError("Could not create test dates")
}

check(week.contains(monday), "ISO week should contain Monday start")
check(week.contains(sunday), "ISO week should contain Sunday")
check(!week.contains(nextMonday), "ISO week should exclude next Monday")
check(ISOWeek(year: 2026, week: 22).shifted(by: 1).id == "2026-W23",
      "shifted week should preserve ISO identity")

// ── ItemArrangement ──────────────────────────────────────────────────────────

func makeItem(_ id: String, zone: String = "Inbox", done: Bool = false,
              day: Int? = nil) -> ProjectItem {
    let date = day.flatMap { calendar.date(from: DateComponents(year: 2026, month: 5, day: $0)) }
    return ProjectItem(id: id, kind: .reminder, rawTitle: id, content: id,
                       containerName: zone, isCompleted: done, date: date,
                       notes: nil, priority: 0, url: nil)
}

// arranged: incomplete before completed, regardless of saved order.
let arranged1 = ItemArrangement.arranged(
    [makeItem("a", done: true), makeItem("b")], savedOrder: ["a", "b"])
check(arranged1.map(\.id) == ["b", "a"], "arranged should put incomplete before completed")

// arranged: among incomplete, follow the saved manual order.
let arranged2 = ItemArrangement.arranged(
    [makeItem("x"), makeItem("y"), makeItem("z")], savedOrder: ["z", "x", "y"])
check(arranged2.map(\.id) == ["z", "x", "y"], "arranged should follow saved order")

// arranged: items absent from saved order fall back to date order, after ranked ones.
let arranged3 = ItemArrangement.arranged(
    [makeItem("late", day: 20), makeItem("early", day: 10), makeItem("ranked")],
    savedOrder: ["ranked"])
check(arranged3.map(\.id) == ["ranked", "early", "late"],
      "arranged should rank saved items first, then order the rest by date")

// groupedByZone: groups sorted by zone, each group keeps incoming order.
let groups = ItemArrangement.groupedByZone(
    [makeItem("b1", zone: "Build"), makeItem("a1", zone: "Admin"),
     makeItem("b2", zone: "Build")])
check(groups.map(\.zone) == ["Admin", "Build"], "groups should sort by zone name")
check(groups.last?.items.map(\.id) == ["b1", "b2"], "group should preserve item order")

// inWeek: keep only items dated within the week, ordered by date.
let weekItems = ItemArrangement.inWeek(
    [makeItem("out", day: 1), makeItem("sun", day: 31), makeItem("mon", day: 25)],
    ISOWeek(year: 2026, week: 22))
check(weekItems.map(\.id) == ["mon", "sun"], "inWeek should filter to the week and sort by date")

print("FacetXCoreChecks OK")
