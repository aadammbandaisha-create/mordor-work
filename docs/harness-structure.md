# Harness structure notes

The upstream `mutwo-skills` harness pattern is worth keeping separate from any
specific feature implementation.

## Module contract

Each harness mod owns a folder:

```text
harness/<mod-name>/
  README.md
  install.ps1
  uninstall.ps1
  scripts/
```

The installer owns only entries tagged with its sentinel:

```text
mordor:<mod-name>
```

That gives three important properties:

- Reinstall is idempotent.
- Uninstall removes only entries the module owns.
- Multiple harness mods can share `~\.claude\settings.json` without fighting.

## Settings mutation rules

Every mod should:

1. Read `~\.claude\settings.json`, creating `{}` if missing.
2. Validate JSON before changing it.
3. Back up the file with a timestamp.
4. Remove prior hook entries containing its sentinel.
5. Add fresh hook entries.
6. Write formatted JSON.
7. Validate JSON again.
8. Restore the backup on failure.

## Hook shape

Claude Code hook entries use this shape:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe ..."
          }
        ]
      }
    ]
  }
}
```

Runtime scripts should be quiet by default. Hook stdout can clutter the user
session, so scripts should write state to files and notifications instead.
(Exception: SessionStart hooks, where stdout IS the injected context.)

## Extended conventions (learned in the field)

- Mods may ship Claude Code skills: `harness/<mod>/skills/<skill>/SKILL.md`,
  installed to `~\.claude\skills\<skill>\`. Ownership = the exact skill dirs.
- Mods may own a Windows scheduled task; the task name is the sentinel
  (e.g. `mordor-daily-digest`).
- PowerShell 5.1 gotchas that have caused real bugs here:
  1. `Get-Content` without `-Encoding UTF8` reads UTF-8 files as ANSI and
     produces mojibake. Always pass the encoding.
  2. `Set-Content -Encoding UTF8` writes a BOM. Node's `JSON.parse` rejects
     BOMs - any JS reading harness-written JSON must strip U+FEFF first.
  3. Calling the `claude` npm shim (claude.ps1) eats a literal `--` argument
     during parameter binding. Route such commands through `cmd /c "..."`.
- UIs reading transcripts assume a 200k context window; clamp percent at 100
  (larger-window models would otherwise overflow the gauge).
