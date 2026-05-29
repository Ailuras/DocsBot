# FacetX — Design

**Status:** v0.1 — all seven build phases implemented; a working pre-release
demo. Supersedes the Python+SQLite+web version (now frozen, archived in git
history). Implemented: project declaration/editing, prefix-based aggregation,
grouped item view, complete/create/delete, per-project week view + goal, menu
bar quick-capture, live refresh on EventKit changes, container selection +
creation, and a standard Settings window (config) separate from the use-only
main window and menu bar.

## 1. What FacetX is

A **native macOS app** that gives a **project-oriented view** over the user's
existing Apple Calendar and Reminders. It is *not* a todo store of its own — the
items live in EventKit (synced via iCloud, visible in Apple's own apps). FacetX
is the lens that groups a *subset* of those items by project — each project a
*facet* of the same underlying data.

Founding intent: existing calendar/reminder tools are flat (lists, calendars);
there is no "project" aggregation dimension. FacetX supplies it.

## 2. The contract

- **Project association = title prefix `ProjectName:`** (ASCII colon).
  Example: `Regulus: 问题最小化&修复bugs` belongs to project `Regulus`.
- Verified necessary: EventKit exposes **no tag API** (EKReminder has 7 props,
  EKEvent none tag-like), so a string prefix on the title is the only reliable
  association mechanism.
- **Projects are a subset.** Items with no recognized project prefix are ignored
  and never modified. Daily-life reminders (shopping, checkups) stay untouched.
- Parser tolerance: accept both ASCII `:` and fullwidth `：` on read (existing
  calendar data uses `：`); write with ASCII `:`.

## 3. Architecture

```
EventKit (Calendar + Reminders)  ← single source of truth for item content
        ▲  read/write + observe .EKEventStoreChanged
        │
Native Swift app (SwiftUI)
  ├─ EventKit service: auth, fetch, filter-by-prefix, write-back
  ├─ Project store (small, project-side metadata only)
  ├─ Main window: project list → project detail (its calendar + reminder items)
  └─ Menu bar item: status, quick open, quick-add to a project
        │
Project store (SwiftData or small SQLite)
  - declared projects (name, the prefix it claims, display meta/tagline)
  - week goals and other project-owned info EventKit can't hold
  - NO item content (that's EventKit's job) → no two-source sync conflict
```

Why this shape:
- Native = EventKit is first-class; no Python↔Swift bridge, no resident-process
  hack. The app is already long-running so it can observe change notifications.
- Project store holds only what EventKit can't, so there is no mirroring/sync
  problem — items are read live and filtered.

## 4. Data model (project store)

```
Project
  id            UUID
  name          String         // e.g. "Regulus"
  prefix        String         // the title prefix it claims, default = name
  tagline       String
  createdAt     Date
  archived      Bool

WeekGoal
  id            UUID
  projectId     UUID
  weekId        String         // ISO "2026-W22"
  title         String
  body          String
```

Items (tasks/events) are NOT stored — fetched from EventKit on demand and
matched by `title.hasPrefix("\(prefix):")` (colon-tolerant).

## 5. EventKit integration notes (from probe)

- Requires a **bundled, code-signed .app** with usage strings
  (`NSRemindersFullAccessUsageDescription`, `NSCalendarsFullAccessUsageDescription`).
  A bare CLI binary is silently denied.
- macOS 14+: `requestFullAccessToReminders` / `requestFullAccessToEvents`.
- Real containers observed: reminder lists 科研待办/任务安排/日常采购/奇思妙想/
  活动提醒; calendars 实现实验/学习交流/思考规划/任务行程/活动爱好.
- Observe `.EKEventStoreChanged` to refresh views when Apple apps or iCloud
  change data.

## 6. Build phases

1. **Project scaffold**: SwiftUI app, LSUIElement optional, EventKit entitlement
   + Info.plist usage strings, ad-hoc signing for local dev.
2. **EventKit service**: auth flow, fetch reminders/events, prefix parser
   (colon-tolerant, newline-safe — real titles contain `\n`).
3. **Project store**: declare/list/archive projects; persist week goals.
4. **Main window**: project list → detail showing that project's reminders
   (grouped by list) and calendar events (grouped by calendar = functional zone).
5. **Write-back**: mark reminder complete, create a reminder/event already
   prefixed with the project name.
6. **Menu bar**: status + quick-add into a chosen project.
7. **Polish**: week view, filtering, empty states.

## 7. Out of scope (for now)

- Apple Notes integration (no public API; AppleScript only; deferred).
- The retired web frontend and Python server.
