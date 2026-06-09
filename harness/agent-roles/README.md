# agent-roles

A director/worker framework for Claude Code subagents, implementing the
token-economy escalation ladder as concrete, loadable roles.

## The model

The main session agent is the **director** (Fable 5). It plans, decides, and
delegates. Five pre-defined roles live in `~\.claude\agents\`, each pinned to
the model tier its work deserves:

| Role | Model | Use for |
| --- | --- | --- |
| `scout` | Haiku | Locating files/symbols/facts; read-only, returns paths + facts |
| `researcher` | Sonnet | Web/docs research; dense cited reports |
| `builder` | Sonnet | Scoped implementation with acceptance criteria |
| `reviewer` | Opus 4.8 | High-importance review; adversarial verification |
| `architect` | Fable 5 | Prime importance: design, security, hard debugging |

A short **director doctrine** is installed into `~\.claude\CLAUDE.md`
(sentinel-owned block), so every session knows the roles exist, when to use
each, and the two standing rules: cheapest role that can do the job, and
self-contained briefs (subagents don't see the conversation).

## Why roles instead of ad-hoc agents

- The model tier is enforced by the role file, not re-decided per spawn.
- Each role's system prompt shapes behavior where it matters: scouts report
  facts without editorializing, builders verify before reporting done,
  reviewers are adversarial by default, architects don't touch files.
- Roles appear in the Agent tool's type list, so the director (and you, via
  `@agent-name` mentions) can invoke them by name.

## Install

```powershell
cd harness\agent-roles
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code (or start a new session) to load the roles.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes the five role files and the doctrine block (only the block — the
rest of `~\.claude\CLAUDE.md` is preserved; the file is backed up first).

## Ownership

- Role files: this mod owns exactly `scout.md`, `researcher.md`,
  `builder.md`, `reviewer.md`, `architect.md` in `~\.claude\agents\`. Other
  agent files are never touched.
- Doctrine: owned via `<!-- mutwo:agent-roles start/end -->` markers in
  `~\.claude\CLAUDE.md`. Install replaces only that block; uninstall removes
  only that block.

## Token note

The doctrine block (~15 lines) loads into every session — that is the point,
and the cost is small. The role files themselves cost nothing until spawned;
only their one-line descriptions appear in the director's agent list.
