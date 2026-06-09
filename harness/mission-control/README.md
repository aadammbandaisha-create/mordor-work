# mission-control

Always-on-top WPF dashboard window showing the state of every active Claude Code
session at a glance, with live context-budget and daily spend in the header.

This supersedes show-claude-state-light.ps1 (windows-state-indicator mod). That
script continues to work and can run alongside this one; they read the same state
directory and do not conflict.

## What it does

- Reads $env:USERPROFILE\.claude\state\*.json every 2.5 seconds (written by the
  windows-state-indicator hooks). One card per session updated within the last 24h,
  newest first, capped at 8.
- Card: leaf folder name of cwd as title; colored dot (working=green, idle=red,
  stale >10min=gray); summary text (~140 chars); relative age ("5m ago").
- Header strip: context % of the most recently updated session (green <60, amber
  <80, red >=80), plus today's estimated API-equivalent spend recomputed at most
  every 30s.
- Dark theme (#1e1e1e window, #2a2a2a cards, #e6e6e6 text).
- Slim custom title bar: "mission control" label, pin toggle (Topmost on/off),
  close button. Draggable; remembers window position in
  $env:USERPROFILE\.claude\mission-control.pos across runs.
- Pure PowerShell + WPF (PresentationFramework/PresentationCore/WindowsBase).
  Zero external dependencies.
- -RenderOnce switch: headless self-test mode -- collects data, prints a plain-text
  dump to stdout, exits 0. No window is shown.

## Requirements

- Windows PowerShell 5.1 (ships with Windows 10/11)
- windows-state-indicator mod installed and active (provides the state/*.json files
  this dashboard reads). Without it the dashboard shows "no active sessions" until
  a Claude Code session runs.

## Install

```powershell
cd harness\mission-control
.\install.ps1         # interactive
.\install.ps1 -Yes    # unattended

# also create a startup shortcut so the dashboard launches at login:
.\install.ps1 -AutoStart
.\install.ps1 -Yes -AutoStart
```

The installer copies show-mission-control.ps1 to
$env:USERPROFILE\.claude\scripts\. With -AutoStart it also creates
mission-control.lnk in shell:startup pointing at the script.

No changes are made to settings.json.

## Run manually

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\show-mission-control.ps1"
```

## Headless self-test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "harness\mission-control\scripts\show-mission-control.ps1" -RenderOnce
```

Reads the real state dir (read-only), prints card count, card details, ctx%, and
spend to stdout, then exits.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes the copied script, the startup .lnk (if present), and the .pos file.
Does not touch settings.json or any other mod's files.

## Ownership

This mod owns exactly:
- $env:USERPROFILE\.claude\scripts\show-mission-control.ps1
- $env:USERPROFILE\.claude\mission-control.pos (runtime, best-effort)
- shell:startup\mission-control.lnk (only when -AutoStart was used)

No settings.json sentinel is needed because this mod makes no settings.json changes.

## Notes

- Context % is derived from the transcript_path in the most recently updated state
  file, using the same logic as the token-economy statusline (last non-sidechain
  assistant message usage fields summed vs 200k window).
- Spend figures are API-equivalent estimates using embedded per-model pricing.
  On a subscription plan they represent value consumed against rate limits, not a
  bill. For exact maintained pricing run: npx ccusage
- The window is crash-proof: each tick runs inside try/catch; a malformed state
  file or transcript is silently skipped.
