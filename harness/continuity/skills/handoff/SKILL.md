---
name: handoff
description: Package up current session work as a self-contained handoff brief so a fresh agent can continue without seeing this conversation. Triggers on /handoff, "handoff", "hand off", "write a handoff", "fresh agent", "sidequest", "spin off", "fork this", "give me a handoff", "make a handoff". Bare invocation = full session scope. Trailing free-text args = scoped sidequest topic.
---

# Handoff

Package the current session as a self-contained brief, then deliver it.

## Step 1 -- parse args and determine delivery mode

Delivery modes:

1. **Save** -- write to `<cwd>\.claude\handoff.md` so the next session auto-ingests it via the continuity hook.
2. **Clipboard** -- `Set-Clipboard` so the user can paste anywhere.
3. **Spawn** -- open a new Windows Terminal pane in the same cwd running `claude`. The brief goes to clipboard first (wt command-line quoting of long strings is fragile), then the pane opens. The user pastes manually once the session starts.

**Destination gate:** if the user named a destination, honor it. Otherwise fire `AskUserQuestion` with header "Handoff to" and options: Save to handoff.md / Copy to clipboard / Spawn new pane (clipboard pre-loaded). Do NOT guess; the gate is mandatory on a bare `/handoff`.

Sidequest scope: any free text in args that is not a destination flag is the sidequest topic. Without it, the handoff covers the full session.

## Step 2 -- compose the brief

Build a brief a fresh agent can act on with no prior context.

Cover only sections that are real for this session:

- **Context** -- relevant CLAUDE.md, MEMORY.md paths; project name and cwd.
- **Completed** -- concrete diff summary ("Changed X from A to B", not narration).
- **In progress** -- exact file paths, function names, line numbers when load-bearing.
- **Decisions and why** -- the constraint or reason behind each decision made.
- **Blockers** -- anything unresolved.
- **Next step** -- first action the receiving agent should take, stated as an imperative.

In sidequest mode scope every section to the topic only; drop main-quest material.

Hard rules: no em-dashes; absolute file paths; self-contained (no "see above"); do not paraphrase the user's sidequest topic.

## Step 3 -- deliver

**Save path:** create `<cwd>\.claude\` if absent, write the brief to `handoff.md` (overwrite). Confirm: "Saved to <path>. The next session will auto-ingest it."

**Clipboard path:** run `Set-Clipboard -Value <brief>`. Confirm: "Copied N chars to clipboard."

**Spawn path:** copy brief to clipboard first, then run:

```powershell
wt -w 0 sp -d "<cwd>" powershell -NoExit -Command "claude"
```

Confirm: "Spawned new pane in <cwd>. Brief is on the clipboard -- paste it once the session starts."

Note: `wt` must be on PATH (Windows Terminal). If the command fails, fall back to clipboard and say so.

## Anti-patterns

- Do not print the full brief back to chat on Save or Spawn paths -- the user already has it.
- Do not skip the destination gate when no destination was given.
- Do not use relative paths in the brief.
