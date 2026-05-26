// Demo project metadata
// This is an example project shipped with DocsBot to demonstrate the data format.

window.AUGUR_META = {
  project: "Demo",
  short:   "Demo",
  tagline: "Example project for DocsBot dashboard",
  description: "A sample project showing how DocsBot renders research directions, engineering backlog, and notes.",
  last_updated: "2026-05-26",
  doc_number: "NB-001",

  repo_url: "https://github.com/example/demo",
  stale_days: 14,

  pages: [
    { id: "index",    label: "Overview", path: "index.html" },
    { id: "research", label: "Research", path: "research.html" },
    { id: "backlog",  label: "Backlog",  path: "backlog.html" },
    { id: "notes",    label: "Notes",    path: "notes.html" },
  ],

  stages: [
    {
      id: "core",
      code: "CORE",
      label: "Core Engine",
      lang: "C++20",
      input:  "Parser / Encoder / Solver wrapper",
      output: "Structured intermediate representation",
      bullet: "The core parsing and transformation pipeline is stable.",
      status: "stable",
      path: "../src/",
    },
    {
      id: "loop",
      code: "LOOP",
      label: "Experiment Loop",
      lang: "Python",
      input:  "Candidate hypotheses + solver feedback",
      output: "Validated or rejected candidates",
      bullet: "The experimental validation loop is actively being refined.",
      status: "active",
      path: "../src/loop/",
    },
  ],

  external_links: [
    { label: "Getting Started", subtitle: "Setup guide", path: "notes/2026-01-15-getting-started.html" },
    { label: "DocsBot Repo",    subtitle: "Dashboard source",   path: "https://github.com/example/docsbot" },
  ],
};
