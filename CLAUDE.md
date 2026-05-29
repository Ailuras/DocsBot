# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS (SwiftUI, macOS 14+) app that layers a **project** dimension over
the user's existing Apple Calendar and Reminders. FacetX stores no item content
of its own — items live in EventKit (synced via iCloud, visible in Apple's apps).
It is a *lens* that gathers the subset of calendar/reminder items belonging to a
project and presents them in one panel (each project = a *facet* of the same
data).

All Swift source lives under [app/Sources/FacetX/](app/Sources/FacetX/).

## Build & run

The app **must run as a bundled, code-signed .app** — a bare SwiftPM binary is
silently denied EventKit access by macOS. Never `swift run`; always build the
bundle:

```bash
cd app
./build-app.sh            # release (default); or ./build-app.sh debug
open ./FacetX.app
./make-dmg.sh             # package FacetX.app into a distributable .dmg
```

`build-app.sh` runs `swift build`, wraps the binary into `FacetX.app` with
[Info.plist](app/Info.plist) (EventKit usage strings) +
[FacetX.entitlements](app/FacetX.entitlements), then ad-hoc code-signs it.
There is no test target.

EventKit permission state is granted per-bundle by macOS (TCC). If you change the
bundle identifier or signing, you may need to re-grant Calendar/Reminders access
(System Settings → Privacy & Security) or `tccutil reset` for the bundle id
(`com.facetx.app`).

## The core contract (do not break)

An item belongs to a project when its **title starts with `ProjectName:`**. This
is the only association mechanism because EventKit exposes no tag API. All of
[ProjectPrefix.swift](app/Sources/FacetX/ProjectPrefix.swift) encodes it:

- **Colon-tolerant on read, ASCII on write.** Accept both ASCII `:` and fullwidth
  `：` when parsing (real calendar data uses `：`); always compose new titles with
  ASCII `:` via `ProjectPrefix.makeTitle`.
- **First-line only.** Real reminder titles contain newlines — the prefix parser
  considers only the first line.
- **Subset semantics.** Items without a recognized prefix are ignored and never
  modified. Daily-life reminders must stay untouched. The app only ever writes
  items it composed with a project prefix.

Always go through `ProjectPrefix` for parsing/composing — never hand-roll prefix
string handling elsewhere.

## Architecture

Three `ObservableObject`s are created in
[FacetXApp.swift](app/Sources/FacetX/FacetXApp.swift) and injected as
environment objects into all three scenes (main `WindowGroup`, `MenuBarExtra`
quick-capture, and the standard `SwiftUI.Settings` window):

- **[EventKitService.swift](app/Sources/FacetX/EventKitService.swift)** — wraps
  `EKEventStore`: auth, fetch, prefix-filter, write-back, container CRUD. This is
  the only file that touches EventKit.
- **`ProjectStore`** ([Models.swift](app/Sources/FacetX/Models.swift)) —
  `@MainActor`; persists declared projects + week goals as JSON under Application
  Support (`FacetX/projects.json`). Holds *only* project-side metadata EventKit
  can't represent (name, claimed prefix, tagline, week goals). **No item content
  is stored here** — that's what avoids any two-source sync problem.
- **[AppSettings.swift](app/Sources/FacetX/AppSettings.swift)** — `@MainActor`;
  persists which containers are enabled (`FacetX/settings.json`).

Both JSON stores resolve their directory through
[AppSupport.swift](app/Sources/FacetX/AppSupport.swift) (`Application
Support/FacetX/`) — change the folder name in that one place if ever needed.

Scene/view split is deliberate: the main window and menu bar are for *use*;
**all configuration lives in the Settings window**
([SettingsScene.swift](app/Sources/FacetX/SettingsScene.swift): declare/edit
projects, choose/create containers). Note the `SwiftUI.Settings` scene must be
fully qualified because our own `ProjectStore`/config naming would otherwise
shadow it.

### Concurrency: EventKitService is NOT @MainActor

This is the most error-prone area. `EventKitService` is `nonisolated` and
`@unchecked Sendable` on purpose:

- EventKit's `fetchReminders` callback fires on its own background queue, and
  `EKEventStore`/`EKReminder` are not `Sendable`. A `@MainActor` wrapper triggers
  Swift 6 main-actor isolation assertions (`dispatch_assert_queue_fail` → SIGTRAP)
  — this actually crashed an earlier build.
- **Flatten non-Sendable EKReminder/EKEvent into the Sendable `ProjectItem`
  struct *inside* the EventKit callback** — never let an `EKReminder` cross an
  actor hop. See `reminders(forProject:)` and `fetchReminderProjectNames`.
- Only the `@Published` auth flags are written back via `MainActor.run`.

If you add EventKit calls, preserve this pattern: stay off the main actor, and
map to value types before returning.

### Live refresh

`EventKitService` observes `.EKEventStoreChanged` and bumps `changeToken`. Views
watch it with `.onChange(of: ek.changeToken) { Task { await reload() } }` so the
UI updates when data changes in Apple's apps or via iCloud.

### Containers keyed by title, not identifier

`AppSettings.enabledContainerNames` and all container lookups use the container
**title**, not `calendarIdentifier` — identifiers are device-local (the same
iCloud calendar has a different id per Mac) while titles are stable across
devices/accounts. An **empty** enabled-set means "all containers" (fresh-install
default). `AppSettings.toggle` materializes "all" into an explicit set before the
first removal so unchecking one doesn't re-enable everything.

## Conventions

- Reads/writes are scoped to enabled containers everywhere via the
  `enabled: Set<String>?` parameter (empty/nil = all). When adding fetch/create
  paths, thread `settings.enabledContainerNames` through.
- Week identity is ISO-8601, Monday-start, formatted `"2026-W22"` — use
  [ISOWeek.swift](app/Sources/FacetX/ISOWeek.swift), don't reimplement week math.
- JSON stores write atomically with `[.prettyPrinted, .sortedKeys]`.
- Keep the dependency surface at zero: pure SwiftPM + system frameworks only
  (this keeps the Command Line Tools build working — no Xcode project required).
