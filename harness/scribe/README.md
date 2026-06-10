# scribe

Capture hard-won lessons from a session as path-scoped project rules so
future sessions start smarter without bloating CLAUDE.md.

## How it works

When you invoke `/scribe`, the agent:

1. Reflects on the session for durable, non-obvious lessons -- gotchas,
   discovered conventions, mistakes not to repeat.
2. Proposes each lesson as a rule: a target glob, a short title, and
   1-4 lines of guidance.
3. Gates every write behind `AskUserQuestion` (multi-select) -- nothing
   is written until you approve.
4. Writes approved rules to `<repo>\.claude\rules\<topic>.md` with YAML
   frontmatter listing the path globs.
5. Confirms what was written.

## The rules/ mechanism

Files under `<repo>\.claude\rules\` with `paths:` frontmatter are loaded
by Claude Code automatically when a file matching one of the listed globs
is edited. This means:

- A rule for `**/*.ps1` appears in context only when PowerShell files are
  touched -- not on every message.
- Rules accumulate over time without growing CLAUDE.md.
- Each topic gets its own file; related lessons are grouped there.

Example rule file (`<repo>\.claude\rules\powershell-quirks.md`):

```markdown
---
paths:
  - "**/*.ps1"
---

## Force single-element arrays through ConvertTo-Json

When serializing to JSON in PS5.1, a single-element array serializes as
a plain object unless you wrap it: ConvertTo-Json -InputObject @($x).
Omitting this caused a real settings.json corruption bug.
```

## Using with close-out

The `continuity` mod installs `/close-out` for end-of-session housekeeping.
The two skills complement each other:

- `/close-out` handles doc updates, memory writes, commits, and handoffs.
- `/scribe` captures reusable path-scoped rules for future sessions.

Run `/scribe` as the "what did we learn" step -- before or after
`/close-out`. Neither skill calls the other automatically; run both when
both are relevant.

## Install

```powershell
cd harness\scribe
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

## Uninstall

```powershell
cd harness\scribe
.\uninstall.ps1
```

## Ownership

| Owned item | What it is |
|---|---|
| `~\.claude\skills\scribe\` | skill directory (whole dir) |

Uninstall removes only the above directory. No hooks, no settings.json
entries, no scripts. Rule files written to project repos are owned by
the project, not this mod -- they are not removed on uninstall.

## Notes

- No hooks, no settings.json writes. This mod is skills-only.
- The skill never writes a rule file without explicit user approval via
  `AskUserQuestion`.
- Rules live in the project repo (`.claude/rules/`), not in
  `~\.claude\`. They are version-controllable and project-scoped.
- "Do NOT scribe" items: task status, secrets, things already in
  CLAUDE.md or git history, transient session state.
