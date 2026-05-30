# FacetX

A **native macOS app** that gives a **project-oriented view** over your existing
Apple Calendar and Reminders.

Your tasks and events already live in Reminders and Calendar (synced via iCloud,
visible in Apple's own apps). Those apps organize them flatly — by list, by
calendar — with no notion of a *project*. FacetX adds that missing dimension:
create a project, and FacetX gathers the subset of your calendar/reminder
items that belong to it into one panel — each project is a *facet* of the same
underlying data.

## How items map to projects

A project owns items by a **title prefix**:

```
Regulus: 问题最小化&修复bugs      →  project "Regulus"
调研: 机器学习+运筹优化            →  ignored (no matching project)
```

Items without a recognized project prefix are never touched — your day-to-day
reminders stay exactly as they are. (EventKit exposes no tag API, so a title
prefix is the only reliable association mechanism — see `REBUILD.md`.)

## Build & run

```bash
cd app
./build-app.sh            # compile + bundle + ad-hoc sign FacetX.app
open ./FacetX.app
```

The app must run as a bundled, signed `.app` — a bare binary is denied EventKit
access by macOS. See [CLAUDE.md](CLAUDE.md) for architecture notes.

## Checks

```bash
cd app
swift build -c debug
swift run FacetXCoreChecks
```

## Status

Native SwiftUI app (v0.2, local beta). The app now includes a polished
three-pane workspace, modern detail and settings surfaces, menu bar quick
capture, project-specific week planning, completed-item controls, and lightweight
core checks. See **[REBUILD.md](REBUILD.md)** for the design.

## Layout

- `REBUILD.md` — design / blueprint
- `CLAUDE.md` — repository guide for future coding agents
- `app/` — the SwiftUI app (sources, checks, build scripts)
