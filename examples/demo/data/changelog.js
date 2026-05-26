// Demo changelog

window.AUGUR_CHANGELOG = [
  {
    sha:     "abc1234567890abcdef1234567890abcdef123456",
    short:   "abc1234",
    date:    "2026-05-20",
    summary: "初步集成验证门到主循环",
    narrative: "为 R1 方向铺设基础设施，候选引理现在经过初步检查后再进入 solver。",
    refs:    ["R1", "P0-02"],
  },
  {
    sha:     "def5678901234abcdef5678901234abcdef567890",
    short:   "def5678",
    date:    "2026-05-15",
    summary: "添加回归测试骨架",
    narrative: "建立了 tests/ 目录和 CMake 集成，为后续 correctness 改动提供安全网。",
    refs:    ["P0-01"],
  },
  {
    sha:     "1234abcd5678ef901234abcd5678ef901234abcd",
    short:   "1234abc",
    date:    "2026-05-10",
    summary: "重构命令构造 helper",
    narrative: "统一了 solver 和外部工具的命令构造逻辑，消除路径拼接带来的潜在问题。",
    refs:    ["P1-02"],
  },
  {
    sha:     "5678ef901234abcd5678ef901234abcd5678ef90",
    short:   "5678ef9",
    date:    "2026-05-01",
    summary: "设计运行记录 manifest 格式",
    narrative: "定义了 JSONL schema，为后续实验可比较性打下基础。",
    refs:    ["R4", "P2-01"],
  },
];
