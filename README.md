# 🧠 my-harness

> One AI brain, every machine.

My personal AI harness: a single source of truth that reproduces the same AI context on every local machine I use to build my tools. It holds a shared, project-agnostic catalog of skills and instructions for AI coding tools (Claude Code, Copilot, ...).

🔗 `run.sh` deploys them by **symlinking** them into the tool directories, so an edit here is live everywhere, instantly. No copy, no drift.

## 🗂️ Layout

```
resources/
├── skills/<skill-name>/                # 🛠️ standalone skill
├── instructions/<name>.instructions.md # 📜 standalone instruction
└── collections/<collection-name>/      # 📦 skills and instructions linked as one unit
    ├── skills/<skill-name>/
    └── instructions/<name>.instructions.md
```

✍️ Authoring rules live in [AGENTS.md](AGENTS.md).

## 📚 What's inside

### 🏠 Self-made

| File | Purpose |
|---|---|
| 📜 `resources/instructions/global.instructions.md` | Cross-workspace rules loaded in every session: interaction style, plan → validation → implementation workflow, guardrails, end-of-answer format |
| 🔒 `personal.instructions.template.md` | Template for local, git-ignored personal instructions (profile, tone, nicknames) |
| ⚙️ `run.sh` + [`run.spec.md`](run.spec.md) | Deployment script and its spec: symlinks `resources/` into each tool directory |
| 🧾 `run.properties.template` | Template for the git-ignored target configuration |
| ✍️ [`AGENTS.md`](AGENTS.md) | Authoring rules for this repository |

### 🌍 Public references

Vendored from public repositories, kept as-is. All credit goes to their authors 🙏

#### 🪨 `caveman` collection

Source: [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) (MIT, skills directory, see [LICENSE](resources/collections/caveman/LICENSE)). Cuts output tokens by making the agent talk like a smart caveman. Pinned versions are tracked in [`skills-lock.json`](skills-lock.json).

| Skill | Purpose |
|---|---|
| `caveman` | Terse communication mode (lite, full, ultra, wenyan) that keeps full technical accuracy |
| `caveman-compress` | Compresses a memory file (CLAUDE.md, todo list) to save input tokens, with a readable backup |
| `caveman-explore` | Read-only repository explorer that returns `path:line` citations only |
| `cavecrew` | Decides when to delegate to compressed-output subagents (investigator, builder, reviewer) |
| `caveman-help` | Quick-reference card for modes, skills and commands |
| `caveman-stats` | Shows token usage and mode attribution for the current session |
| `caveman-learn` | Acts on a learn report: ranks token sinks and applies cost-lowering fixes with consent |
| `caveman-optimize` | Turns an optimization observation into a candidate with a paired baseline evaluation |

#### 🧑‍🏫 `mattpocock` collection

Source: [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, see [LICENSE](resources/collections/mattpocock/LICENSE)). Engineering workflow skills "for real engineers".

| Skill | Purpose |
|---|---|
| `ask-matt` | Router: tells you which skill or flow fits your situation |
| `setup-matt-pocock-skills` | One-time repo setup: issue tracker, triage labels, domain doc layout |
| `grill-me` / `grilling` | Relentless interview to stress-test a plan or design |
| `grill-with-docs` | Same interview, writing ADRs and a glossary along the way |
| `to-questionnaire` | Turns an open decision into a questionnaire for someone else |
| `to-spec` | Synthesizes the conversation into a spec on the issue tracker |
| `to-tickets` | Breaks a plan or spec into tracer-bullet tickets with blocking edges |
| `wayfinder` | Plans work too big for one session as a map of decision tickets |
| `triage` | Moves issues and external PRs through a triage state machine |
| `implement` | Implements work from a spec or a set of tickets |
| `tdd` | Test-first red-green-refactor loop |
| `prototype` | Throwaway prototype to answer a design question |
| `diagnosing-bugs` | Diagnosis loop for hard bugs and performance regressions |
| `code-review` | Reviews changes since a fixed point against standards and spec |
| `resolving-merge-conflicts` | Resolves an in-progress merge or rebase conflict |
| `codebase-design` | Shared vocabulary for designing deep modules |
| `improve-codebase-architecture` | Finds deepening opportunities and reports them as HTML |
| `domain-modeling` | Builds the domain model: CONTEXT.md and ADRs |
| `research` | Investigates primary sources and writes findings to Markdown |
| `teach` | Teaches a new skill or concept inside the workspace |
| `writing-for-agents` | Guidance for writing skills, AGENTS.md and CLAUDE.md |
| `wizard` | Generates an interactive bash wizard for steps only a human can do |
| `handoff` | Compacts the conversation into a handoff document |
| `claude-handoff` | Hands the conversation off to a fresh background agent |
| `wait-what` | Forces a re-pitch when the last message did not land |

#### 🏆 `awwwards` skill

Source: [tponscr-debug/claude-skill-awwwards](https://github.com/tponscr-debug/claude-skill-awwwards) (MIT, declared in its [README](resources/skills/awwwards/README.md#license)). Creative-direction skill for Awwwards-level frontend work: typography, color, layout, motion, CSS techniques, WebGL, with reference files.

### 🙏 Thanks

Huge thanks to [Julius Brussee](https://github.com/JuliusBrussee), [Matt Pocock](https://github.com/mattpocock) and [tponscr-debug](https://github.com/tponscr-debug) for sharing their work publicly. Go star their repositories ⭐

## 🚀 Setup

Requires **bash >= 4.4** (🍎 on macOS: `brew install bash`).

```sh
cp run.properties.template run.properties   # git-ignored, adjust the target directories
./run.sh list
```

🔒 Optional personal instructions, kept local (git-ignored):

```sh
cp personal.instructions.template.md resources/instructions/personal.instructions.md
```

## 🕹️ Usage

```sh
./run.sh <command> [--no-color]
```

| Command | Mode | Description |
|---|---|---|
| 🔍 `list` | read-only | Status of every resource; exits non-zero on problems, so it can be used as a check |
| 🔗 `link` | interactive | Select collections and elements to symlink |
| ✂️ `unlink` | interactive | Select linked collections and elements to remove |
| 🧹 `clean` | interactive | Delete dead symlinks after one confirmation |
| 🩹 `fix` | automatic | Relink broken elements and resync collections whose content changed |
| 🗑️ `purge` | interactive | Delete Claude Code plugin cache entries (`<claude.home>/plugins/cache`) |
| ❓ `help` | read-only | Commands and resolved configuration |

⌨️ Menus accept arrow keys or `j`/`k`, `space`, `a` (all) and `enter`. When stdin is not a terminal, they fall back to a numbered prompt:

```sh
echo "1 3" | ./run.sh link
```

## 🛡️ Safety

`run.sh` only creates or deletes symlinks that point into `resources/`. Your other files are never touched.

📖 Full behavior is specified in [run.spec.md](run.spec.md).
