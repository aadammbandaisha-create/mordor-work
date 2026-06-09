# mutwo Windows Claude harness

Windows-oriented clone of the `mutwo-skills` harness structure for Claude Code.

This copy focuses on harness mods, not skills. It keeps the upstream shape:

```text
harness/
  <mod-name>/
    README.md
    install.ps1
    uninstall.ps1
    scripts/
```

## What is included

- `harness/windows-state-indicator`: a Windows adaptation of the upstream tab-state indicator.
- Sentinel-tagged hook ownership using `mutwo:windows-state-indicator`.
- Idempotent install and uninstall.
- Settings backup before edits.
- JSON validation before and after settings changes.
- PowerShell scripts copied into `~\.claude\scripts`.
- Optional always-on-top green/red state light.

## Install

From PowerShell:

```powershell
cd C:\Users\qq\Desktop\mutwo-windows-claude-harness
.\install.ps1
```

For unattended install:

```powershell
.\install.ps1 -Yes
```

Restart Claude Code after installing so it picks up hook changes.

## Uninstall

```powershell
.\uninstall.ps1
```

## Important Windows difference

The upstream macOS version changes iTerm2 tab colors with terminal escape codes.
Windows Claude Code cannot reliably color an existing terminal tab from a hook
subprocess. This version instead:

- writes live state into `~\.claude\state\<session_id>.json`;
- sends a Windows notification when Claude stops or asks a question;
- includes `watch-claude-state.ps1` to update the current terminal title from
  the latest state file;
- includes `show-claude-state-light.ps1` for a visible green/red desktop light.

## Upstream

Original repo cloned locally at:

```text
C:\Users\qq\Desktop\mutwo-skills
```

Original GitHub repo:

```text
https://github.com/mujtaba3B/mutwo-skills
```
