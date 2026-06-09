# format-on-edit

PostToolUse auto-formatter: after Claude edits or writes a file, the project's
own formatter runs on it automatically -- silently, non-blocking.

## What it does

When Claude uses the Edit or Write tool, a PostToolUse hook fires
`scripts\format-on-edit.ps1`. The script:

1. Reads the file path from the hook's stdin JSON.
2. Skips the file if it is missing, over 1 MB, or inside `node_modules`,
   `.git`, `dist`, or `build`.
3. Dispatches to the project-local formatter for the file extension:

   | Extension | Formatter (project-local only) |
   | --- | --- |
   | .js .jsx .ts .tsx .json .css .scss .md .html .yml .yaml | walks up for `node_modules\.bin\prettier.cmd`; falls back to `biome.cmd` |
   | .py | `ruff format` -- only if `ruff` is on PATH AND a `pyproject.toml` or `ruff.toml` is found walking up |
   | .ps1 .psm1 | `Invoke-Formatter` from PSScriptAnalyzer -- only if the module is installed |
   | anything else | silent no-op |

4. Runs the formatter with a 15-second hard timeout, then kills it if it
   exceeds that.
5. Always exits 0. Never prints to stdout (stdout from PostToolUse hooks
   injects into conversation context).

### Format-only philosophy

This mod only formats -- it never lints, type-checks, or fails the tool call.
Claude's edit lands regardless of the formatter's outcome. This is intentional:
formatting is mechanical and reversible; a hook that blocks or changes exit
codes would break Claude's tool loop on formatter errors, config issues, or
missing dependencies.

### Extending the dispatch table

To add a language, open `scripts\format-on-edit.ps1` and add a branch to the
`dispatch by extension` section. Follow the same pattern:

- Guard on a project-local binary found by walking up the directory tree.
- Use `Invoke-WithTimeout` with a 15-second timeout.
- Never install anything; never use a global fallback.
- Write debug output only via `Write-DebugLog`.

### Future: exit-2 feedback variant (not implemented)

Claude Code reserves exit code 2 for hooks that want to surface a message
back to the model. A future `format-on-edit-strict` variant could exit 2 with
a message on stdout when the formatter reports unfixable issues (e.g., a parse
error it cannot auto-fix). That variant would require the user to consciously
opt in because it changes the format-only / never-blocks guarantee.

## Install

```powershell
cd harness\format-on-edit
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code to activate the hook.

## Uninstall

```powershell
cd harness\format-on-edit
.\uninstall.ps1
```

## Debug logging

Set the environment variable `CLAUDE_FORMAT_DEBUG=1` in your shell before
starting Claude Code. One line per dispatch decision is appended to
`~\.claude\format-on-edit.log`.

## Ownership

- Hook entry: `hooks.PostToolUse` entry whose command contains the sentinel
  `mordor:format-on-edit`. Install adds exactly one such entry (idempotent on
  re-run). Uninstall removes only entries that contain this sentinel; all other
  mods' PostToolUse entries (e.g., `mordor:windows-state-indicator`) survive.
- Script file: `~\.claude\scripts\format-on-edit.ps1`.
- A timestamped backup of `settings.json` is created before any write. If the
  write fails, the backup is restored automatically.

## Security and cost notes

- The hook runs every time Claude uses Edit or Write. It spawns a subprocess
  per edit. For very large projects with many sequential edits, this adds
  latency (bounded to 15 s per file by the kill timeout).
- Only project-local formatters are ever invoked. There is no network access
  and no package installation.
- PSScriptAnalyzer writes the file back only if the formatted content differs
  from the original, avoiding unnecessary writes.
