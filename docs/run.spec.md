# `run.sh` specification

Deployment script that symlinks resources from this repository into the tool directories (Claude, Copilot, ...).

## Sources

Only the `resources/` folder is symlinkable.

```
resources/
├── skills/<skill-name>/               # standalone skill (directory)
├── instructions/<name>.instructions.md # standalone instruction (file)
└── collections/<collection-name>/
    ├── skills/<skill-name>/
    └── instructions/<name>.instructions.md
```

- **Unit element**: a standalone skill (directory) or instruction (file).
- **Collection**: a group of skills and instructions that work together. A collection is the smallest selectable unit for its content: linking or unlinking a collection applies to all of its skills and instructions. You cannot select one element of a collection on its own.

## Targets configuration

- `run.properties.template`: under source control. It documents every key and has placeholder values.
- `run.properties`: the local copy, added to `.gitignore`. The script reads it and stops with an explicit error if it is missing (the message says to copy the template).

```properties
# Directory receiving skill symlinks (one symlinked directory per skill)
skills.target=~/.claude/skills
# Directory receiving instruction symlinks (one symlinked file per instruction)
instructions.target=~/.claude/rules
# Claude Code user directory, used by `purge`
claude.home=~/.claude
```

- `~` and `$HOME` are expanded. A target directory that does not exist is created on `link`.
- Skills and instructions from collections go to the same targets as standalone elements.

## Link model

- Skill: `<skills.target>/<skill-name>` → `<repo>/resources/.../skills/<skill-name>`
- Instruction: `<instructions.target>/<file>` → `<repo>/resources/.../instructions/<file>`
- Symlinks use absolute paths.
- **Managed symlink**: a symlink in a target directory whose destination resolves under `<repo>/resources/`. The script only creates, modifies or deletes managed symlinks. It never touches regular files, directories, or symlinks pointing elsewhere.
- **Conflict**: the target path already exists and is not a managed symlink to the expected source. The element is skipped and reported; nothing is overwritten.
- **Dead symlink**: a managed symlink whose destination no longer exists.

## Statuses

| Scope | Status | Meaning |
|---|---|---|
| Element | `linked` | Correct symlink present |
| Element | `unlinked` | No symlink |
| Element | `broken` | Managed symlink points to a wrong or missing source for this element (e.g. resource moved) |
| Element | `conflict` | Target path occupied by something not managed |
| Collection | `linked` | All elements `linked` |
| Collection | `partial` | At least one element linked and at least one not (typically after the collection was modified) |
| Collection | `unlinked` | No element linked |
| Orphan | `dead` | Managed symlink with no existing source (not tied to any current element) |

## Commands

### `list`

Read-only. Shows the status of every resource, grouped in this order:

1. **Collections**: one line per collection with its status, then its elements indented with their own status.
2. **Unit elements**: skills, then instructions, one line each with its status.
3. **Dead symlinks**, if any, with a hint to run `clean`.

The command ends with a count per status. It exits with a non-zero code if any element is `broken`, `partial`, `conflict` or `dead`, so it can also be used as a check.

### `link`

Interactive. Offers the selectable units that are not fully linked: collections that are `unlinked` or `partial`, and unit elements that are `unlinked`. Multiple choices can be selected. Selecting a collection links all of its elements. Elements in `conflict` are reported and skipped. The command ends with a summary of what was created.

### `unlink`

Interactive. Offers the selectable units that are linked: collections that are `linked` or `partial`, and unit elements that are `linked`. Multiple choices can be selected. Selecting a collection removes the symlinks of all its elements. Only managed symlinks are removed.

### `clean`

Lists all dead symlinks in the target directories, then asks for a single confirmation (`y/N`, default no) before deleting them. It does nothing if there are no dead symlinks.

### `fix`

Non-interactive repair, idempotent:

- `broken` element: recreate the symlink to the correct source.
- Modified collection: a collection that is `partial`, or that has dead symlinks pointing into `resources/collections/<name>/`, is resynced. The script links the elements added to the collection and removes the symlinks of elements that were removed from it. The collection is considered wanted because at least one of its elements is linked.
- It does not link units that are fully `unlinked`, and it does not resolve `conflict` (reported only).

The command prints each action it performs.

### `purge`

Interactive. Cleans the Claude Code plugin cache (`<claude.home>/plugins/cache/<marketplace>/<plugin>/`). Claude Code keeps the skills and instructions of plugins there, and they are left behind after a plugin is uninstalled.

- Offers every cached plugin as `<plugin>@<marketplace>`, with its cached versions and disk size. Plugins that are no longer listed in `<claude.home>/plugins/installed_plugins.json` are tagged `orphan` and listed first.
- Multiple choices can be selected (with select all). A single `y/N` confirmation, default no, repeats what will be deleted before anything is removed.
- Deletes the selected `<plugin>/` directories, then removes marketplace directories left empty. It never touches `installed_plugins.json`, `marketplaces/`, or anything outside `plugins/cache/`.
- It does nothing if the cache is empty. The command ends with the space freed.

A plugin that is still installed will be downloaded again by Claude Code the next time it starts.

### `help` (alias `about`)

Read-only. Prints a short description of the script, then each command with a one-line summary of what it does and whether it is interactive, read-only or modifies symlinks. It also shows the configuration file in use (`run.properties`) and the resolved target directories, or says that the file is missing.

Running the script without a command shows `help`. An unknown command prints an error followed by `help` and exits with a non-zero code.

## User experience

The script is meant to be pleasant for developers to use day to day.

- **Colors**: each status has its own color and symbol, used the same way in every command:

  | Status | Color | Symbol |
  |---|---|---|
  | `linked` | green | `✔` |
  | `unlinked` | dim / grey | `○` |
  | `partial` | yellow | `◐` |
  | `broken`, `dead` | red | `✖` |
  | `conflict` | magenta | `!` |

  Section headings are bold. Paths are dimmed so names stand out. Errors go to stderr in red, and warnings are in yellow.
- **Interactive selection** (`link`, `unlink`, and every other multi-choice prompt): a checkbox menu drawn in the terminal. The first entry is always `[ ] Select all`: toggling it checks or unchecks every entry, and it shows as checked when every entry is checked. Arrow keys or `j`/`k` move, `space` toggles, `a` is a shortcut for select all, `enter` confirms, `q`/`esc` cancels. Collections show their element count and status. The cursor is hidden while the menu is open and always restored on exit, including on `Ctrl+C`.
- **Confirmations** (`clean`, `purge`): an inline `y/N` prompt with the default shown clearly.
- **Feedback**: every action prints one line with its symbol (e.g. `✔ linked skill foo`). Each command ends with a one-line colored summary.
- **Degradation**: colors are turned off when stdout is not a TTY, when `NO_COLOR` is set, or with `--no-color`. When stdin is not a TTY, the checkbox menu falls back to a numbered prompt (`1 3 5`, `a` for all, empty to cancel), so the script can be used in pipes.

## Constraints

- Bash >= 4.4, no external dependency (no `fzf`, `gum`, `dialog`...). The whole UI uses ANSI escape codes and `read` only.
- Name collision between two sources targeting the same symlink (e.g. same skill name in a collection and in `resources/skills/`): the elements get the `collision` status (red `✖`), reported as an error by `list` (non-zero exit) and refused by `link` and `fix`; the other elements of a collection are still linked.
- No command overwrites or deletes anything that is not a managed symlink, except `purge`, which only deletes inside `<claude.home>/plugins/cache/` after an explicit confirmation.

## Deferred

- Multiple targets per type (e.g. Claude **and** Copilot at the same time): not supported yet, one target per type. If added, prefer one set of keys per tool (e.g. `claude.skills.target`, `copilot.skills.target`) over comma-separated lists, since tool formats may diverge; element statuses then become per target.