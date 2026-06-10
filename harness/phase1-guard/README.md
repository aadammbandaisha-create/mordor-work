# phase1-guard

A PreToolUse safety guard for Claude Code on Windows.

**Default mode: LOG-ONLY. This mod never blocks any command by default.**

The guard watches for destructive shell patterns and silently records what it
would have blocked. You review the log, judge the false-positive rate against
the real-threat rate, then promote to enforce mode when you are ready.

Shipping a guard that starts enforcing immediately would break workflows before
trust is established. Ship log-only first.

## What it does

On every Bash tool call, `guard-check.ps1` is invoked as a PreToolUse hook.
It reads the command from stdin JSON and tests it against the pattern list
below. On a match it writes one JSON line to `~\.claude\guard-log.jsonl` and
exits 0 (allow). On no match it exits 0 immediately.

In `enforce` mode (opt-in via env var) a match instead writes a message to
stderr and exits 2, which causes Claude Code to block the tool call and show
the error to the model.

## Destructive patterns watched

The following patterns are matched case-insensitively:

| Category | What is matched |
| --- | --- |
| Unix hard-delete | `rm -rf`, `rm -fr` and variants |
| Windows rmdir | `rd /s`, `rmdir /s` |
| Windows del with wildcards | `del /f *`, `del /q *` |
| PowerShell Remove-Item | `-Recurse` + `-Force` together |
| git reset | `git reset --hard` |
| git clean | `git clean -fd`, `git clean -df` |
| git force-push | `git push --force`, `git push -f` |
| git checkout wipe | `git checkout -- .`, `git checkout .` |
| Config overwrite | `>` redirection onto known settings.json paths |
| Drive format | `format C:` (any drive letter) |
| diskpart | bare `diskpart` invocation |
| cipher wipe | `cipher /w` |
| takeown | `takeown` invocation |
| ACL grant all | `icacls ... /grant everyone` |
| Fork bomb | `:(){` |
| Shutdown | `shutdown`, `Stop-Computer` |
| Storage wipe | `Format-Volume`, `Clear-Disk` |

The full regex list lives at the top of `scripts\guard-check.ps1`. Edit it
there to add or remove patterns before or after install.

## Review the log

```powershell
powershell -File "$env:USERPROFILE\.claude\scripts\review-guard-log.ps1"
```

This prints counts by pattern and the last 20 flagged entries (timestamp,
tool, matched pattern, command prefix).

Log location: `~\.claude\guard-log.jsonl` (newline-delimited JSON, one entry
per flagged event). The log is never deleted by uninstall -- it is your audit
trail.

## Promote to enforce mode

Set the environment variable `MORDOR_GUARD_MODE=enforce` before starting
Claude Code. The guard will then exit 2 on a match, blocking the tool call and
writing the pattern name to stderr.

Example (PowerShell session before launching Claude Code):

```powershell
$env:MORDOR_GUARD_MODE = "enforce"
claude
```

To make it permanent, add the env var to your user environment via System
Properties or `settings.json`:

```json
{
  "env": { "MORDOR_GUARD_MODE": "enforce" }
}
```

Revert to log-only by removing the variable or setting it to anything other
than `enforce`.

## Install

```powershell
cd harness\phase1-guard
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code to activate the hook.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes the PreToolUse hook entry and both scripts. **Does not delete
`guard-log.jsonl`** -- that file is your audit data; remove it manually if
you no longer need it.

## Ownership

The hook command embeds the sentinel `mordor:phase1-guard` as a trailing
inert argument. The installer's `Remove-OwnedEntries` function filters only
entries containing that sentinel, leaving all other mods' PreToolUse entries
(such as windows-state-indicator's `AskUserQuestion` entry) untouched.

## Security / cost notes

- The hook script runs in-process with Claude Code's PowerShell invocation.
  It never network-calls, never reads project files.
- Log entries contain the first 400 characters of the matched command, not the
  full stdin payload.
- In log-only mode the script is entirely passive: no exceptions thrown, no
  output to stdout, no side effects other than appending to the log file.
- Regex matching on the raw command string means context-blind: a comment
  containing `rm -rf` will match. Review false positives in the log before
  promoting to enforce.
