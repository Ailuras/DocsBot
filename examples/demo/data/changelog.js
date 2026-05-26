// Demo changelog

window.AUGUR_CHANGELOG = [
  {
    sha:     "abc1234567890abcdef1234567890abcdef123456",
    short:   "abc1234",
    date:    "2026-05-20",
    summary: "Integrate validation gate into main loop",
    narrative: "Laid infrastructure for R1. Candidate lemmas now pass a preliminary check before entering the solver.",
    refs:    ["R1", "P0-02"],
  },
  {
    sha:     "def5678901234abcdef5678901234abcdef567890",
    short:   "def5678",
    date:    "2026-05-15",
    summary: "Add regression test skeleton",
    narrative: "Set up tests/ directory with CMake integration, providing a safety net for future correctness changes.",
    refs:    ["P0-01"],
  },
  {
    sha:     "1234abcd5678ef901234abcd5678ef901234abcd",
    short:   "1234abc",
    date:    "2026-05-10",
    summary: "Refactor command builder helpers",
    narrative: "Unified command construction logic for solver and external tools, eliminating path-joining bugs.",
    refs:    ["P1-02"],
  },
  {
    sha:     "5678ef901234abcd5678ef901234abcd5678ef90",
    short:   "5678ef9",
    date:    "2026-05-01",
    summary: "Design run manifest format",
    narrative: "Defined JSONL schema for experiment manifests, laying groundwork for reproducible comparisons.",
    refs:    ["R4", "P2-01"],
  },
];
