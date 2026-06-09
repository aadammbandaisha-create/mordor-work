# continuity

Session-to-session continuity for Claude Code on Windows. Every new session
gets automatic context injection (git state, pending handoff), and two skills
make it easy to package work for hand-off and wrap up cleanly.

## What it installs

1. **SessionStart hook** -- `~\.claude\scripts\session-context.ps1`

   Runs at the start of every Claude Code session. Emits injected context:

   - Current git branch, `git status --short` (capped at 25 lines), last 3 commits.
   - Contents of `<cwd>\.claude\handoff.md` if the file exists and is younger
     than 7 days, with the date it was written and a reminder to delete it.

   Nothing is emitted when `source` is `"compact"` (the conversation already
   carries context), or when the cwd is not a git repo and no handoff file exists.

2. **handoff skill** -- `~\.claude\skills\handoff\SKILL.md`

   Invoke `/handoff` to package the current session as a self-contained brief.
   Three delivery options (gated unless you name one):

   - **Save** -- writes `<cwd>\.claude\handoff.md`; auto-ingested next session.
   - **Clipboard** -- `Set-Clipboard` for pasting anywhere.
   - **Spawn** -- opens a new Windows Terminal pane (`wt -w 0 sp`) in the same
     cwd with `claude` running; brief is on the clipboard to paste in.

   Bare `/handoff` = full-session scope. Trailing text = scoped sidequest.

3. **close-out skill** -- `~\.claude\skills\close-out\SKILL.md`

   Invoke `/close-out` for end-of-session housekeeping:
   - Updates existing repo docs (README/CLAUDE.md/LOG.md) where warranted.
   - Gates every memory write behind an explicit `AskUserQuestion` multi-select.
   - Offers to commit and to write a handoff for unfinished work.

## Install

```powershell
cd harness\continuity
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code to activate the hook.

## Uninstall

```powershell
.\uninstall.ps1
```

## Ownership

| Owned item | What it is |
|---|---|
| `SessionStart` hook in `settings.json` | tagged `mordor:continuity` as trailing arg |
| `~\.claude\scripts\session-context.ps1` | runtime hook script |
| `~\.claude\skills\handoff\` | skill directory (whole dir) |
| `~\.claude\skills\close-out\` | skill directory (whole dir) |

Uninstall removes only the above. Other mods' hook entries are preserved by the
sentinel filter -- only entries whose command contains `mordor:continuity` are removed.

## Notes

- The hook script is quiet and crash-proof: `$ErrorActionPreference = "SilentlyContinue"`,
  always exits 0. A git or file failure produces no output and no error.
- Handoff files older than 7 days are silently skipped -- stale context is worse
  than no context.
- The spawn delivery mode requires Windows Terminal (`wt`) on PATH. If `wt` is not
  found, the skill falls back to clipboard automatically.
- No network calls, no external dependencies beyond `git` (optional).
