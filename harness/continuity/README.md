# continuity

Session-to-session continuity for Claude Code on Windows. Every new session
gets automatic context injection (git state, project map, open markers, test
status, pending handoff), and three skills make it easy to map the repo, package
work for hand-off, and wrap up cleanly.

## What it installs

1. **SessionStart hook** -- `~\.claude\scripts\session-context.ps1`

   Runs at the start of every Claude Code session. Injects context in this order:

   - **## Session context** -- current git branch, `git status --short` (capped
     at 25 lines), last 3 commits.
   - **## Project map** -- contents of `<cwd>\.claude\project-map.md` if present
     (capped at 120 lines). Written by the `/map` skill; lets sessions skip
     re-scouting the repo.
   - **## Open markers: N TODO/FIXME on this branch** -- fast `git grep` count of
     TODO/FIXME on tracked files, plus the top 3 file paths. Shown only when N>0.
     The grep runs in a background job with a 3-second timeout; skipped silently if
     it times out or errors.
   - **## Last recorded test status** -- first line of `<cwd>\.claude\last-test-status.txt`
     if the file exists and is younger than 7 days. (Written by a separate mod;
     continuity only reads it.)
   - **## Pending handoff** -- contents of `<cwd>\.claude\handoff.md` if it exists
     and is younger than 7 days, with the write timestamp and a reminder to delete it.

   Nothing is emitted when `source` is `"compact"` (the conversation already
   carries context), or when the cwd is not a git repo and no injected files exist.

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

4. **map skill** -- `~\.claude\skills\map\SKILL.md`

   Invoke `/map` (or "map the project", "refresh project map", "generate project
   map") to survey the repo and write a concise project map to
   `<cwd>\.claude\project-map.md` (max 120 lines). The file is automatically
   injected at each subsequent session start via the SessionStart hook, so future
   sessions do not need to re-scout the codebase.

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
| `~\.claude\skills\map\` | skill directory (whole dir) |

Uninstall removes only the above. Other mods' hook entries are preserved by the
sentinel filter -- only entries whose command contains `mordor:continuity` are removed.

The project-specific files `<cwd>\.claude\project-map.md` and
`<cwd>\.claude\last-test-status.txt` are NOT owned by this mod; they are written
by the `/map` skill and a separate test-status mod respectively. Uninstall leaves
them in place.

## Notes

- The hook script is quiet and crash-proof: `$ErrorActionPreference = "SilentlyContinue"`,
  always exits 0. A git or file failure produces no output and no error.
- Handoff files older than 7 days are silently skipped -- stale context is worse
  than no context.
- The `git grep` for TODO/FIXME markers runs in a PowerShell background job capped
  at 3 seconds. On very large repos or slow disks it may be skipped silently.
- The spawn delivery mode in the handoff skill requires Windows Terminal (`wt`) on
  PATH. If `wt` is not found, the skill falls back to clipboard automatically.
- No network calls, no external dependencies beyond `git` (optional).
