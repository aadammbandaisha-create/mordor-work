# check-on-edit

Runs cheap project-local lint and type checks on the file Claude just
edited, and surfaces failures as feedback on Claude's next turn.

The strict sibling of `format-on-edit`. Where format-on-edit silently
fixes style, check-on-edit loudly reports semantic problems that only the
author can fix.

## What it does

A `PostToolUse` hook fires on every `Edit` and `Write` tool call. The hook
script reads the file path from stdin JSON, runs the cheapest applicable
checker it can find locally, and:

- exits 0 with no output -- checker clean, tooling absent, guard tripped
- exits 2 with checker output on stderr -- checker found problems

The exit-2 path is the feedback mechanism: Claude Code treats a non-zero
hook exit as a signal and shows the stderr text before Claude's next
response. Claude then reads the lint error in context and can act on it
immediately, without a separate "please run the linter" turn.

The edit already happened (`PostToolUse` fires after the tool completes).
Exit 2 does not block or revert anything; it only informs.

## Dispatch table

| Extension | Tool required | Discovery |
| --- | --- | --- |
| `.py` | `ruff` in PATH | `pyproject.toml` or `ruff.toml` found walking up from file |
| `.ts` `.tsx` | `node_modules\.bin\tsc[.cmd]` | walk up from file; falls through to eslint if absent |
| `.ts` `.tsx` `.js` `.jsx` | `node_modules\.bin\eslint[.cmd]` | walk up from file |
| `.ps1` `.psm1` | `PSScriptAnalyzer` module | `Get-Module -ListAvailable` |

All tools are project-local (node_modules) or system-scoped (ruff,
PSScriptAnalyzer). Global installs are never assumed. If the tool is
absent, the hook exits 0 silently.

## Extending the dispatch table

Add a new `if ($ext -eq ".xxx")` block in
`scripts\check-on-edit.ps1` following the same pattern:

1. Locate the tool binary (walk up with `Find-FileUpward` for
   project-local tools; `Get-Command` for system tools).
2. Bail to `exit 0` if absent or no config found.
3. Call `Invoke-Checker -Exe ... -Arguments ...` (12 s timeout, captures
   stdout+stderr, returns `$null` on error/timeout).
4. If exit code non-zero and output non-empty: call `Exit-WithProblems`.
5. Otherwise `exit 0`.

Do not change the guards (size, path exclusions) or the `Invoke-Checker`
timeout logic -- they protect against false positives and hangs.

## Guards (silent exit 0)

- File does not exist or is not a regular file
- File is larger than 1 MB
- Path contains `node_modules`, `.git`, `/dist/`, or `/build/`
- Checker binary not found
- No config file found up-tree (for ruff)
- Checker process errors or times out

The rule: any doubt about tooling quality -> exit 0. Claude should only
see exit 2 when the checker ran cleanly and genuinely found a problem.

## Install

```powershell
cd harness\check-on-edit
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code to activate the hook.

## Uninstall

Remove the hook entry from `~\.claude\settings.json` by deleting the
`PostToolUse` array element whose command contains `mordor:check-on-edit`,
then delete `~\.claude\scripts\check-on-edit.ps1`.

A dedicated `uninstall.ps1` can be added following the same sentinel-filter
pattern used by `Remove-OwnedEntries` in `install.ps1`.

## Ownership

- Hook entry: `PostToolUse` matcher `Edit|Write`, sentinel `mordor:check-on-edit`
- Script: `~\.claude\scripts\check-on-edit.ps1`

`Remove-OwnedEntries` in `install.ps1` filters only entries containing
`mordor:check-on-edit`. The `format-on-edit` entry (sentinel
`mordor:format-on-edit`) and the `windows-state-indicator` entry (sentinel
`mordor:windows-state-indicator`) are never touched.

## Debug

```powershell
$env:CLAUDE_CHECK_DEBUG = "1"
```

Appends one line per event to `~\.claude\check-on-edit.log`.

## Security / cost notes

- Only project-local binaries are executed (no global npm, no pip). A
  malicious `node_modules/.bin/eslint` could run arbitrary code -- same
  risk as running `npm install` in that project.
- `ruff` and `PSScriptAnalyzer` are system-level; trust is the same as
  running them manually.
- The hook runs on every Edit/Write. ruff and eslint are fast (<1 s on
  typical files). `tsc --noEmit` on a large project can be slow; the 12 s
  timeout kills it and exits 0 silently.
- No network calls are made by the hook script.
