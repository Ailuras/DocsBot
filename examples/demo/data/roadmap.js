// Demo roadmap

window.AUGUR_ROADMAP = {
  label: "2026-Q1",
  focus: {
    week_label: "2026-W05",
    narrative: "The main focus this week is stabilizing the core parser and setting up the regression suite. R1 (validation gate) is the highest-priority research direction.",
    research_ids: ["R1"],
  },
  weeks: [
    {
      label: "Week 5 (current)",
      items: [
        { text: "Set up minimal regression test suite", refs: ["P0-01"] },
        { text: "Wire validation gate into main solver loop", refs: ["P0-02", "R1"] },
        { text: "Write architecture overview note", refs: ["P5-01"] },
      ],
    },
    {
      label: "Week 6 (next)",
      items: [
        { text: "Add parser round-trip property tests", refs: ["P1-01"] },
        { text: "Sanitize shell command construction", refs: ["P1-02"] },
      ],
    },
    {
      label: "Later",
      items: [
        { text: "Design run manifest schema", refs: ["P2-01", "R4"] },
        { text: "Batch runner CLI skeleton", refs: ["P3-01", "R5"] },
        { text: "Alphabet analyzer prototype", refs: ["P4-01", "R2"] },
      ],
    },
  ],
};
