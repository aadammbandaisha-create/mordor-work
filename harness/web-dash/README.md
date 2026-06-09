# web-dash

A local web dashboard for Claude Code on Windows. Shows active session
state, context usage, 7-day spend, and a prompt deck - all from a single
Node 24 HTTP server with zero npm dependencies.

## What it does

- **Session cards** - lists all sessions updated in the last 24h with state
  dot (working/idle), project title, summary, and age.
- **Context gauge** - horizontal bar showing context window % for the newest
  session (computed from its transcript; thresholds 60%=yellow, 80%=red).
- **Today spend** - API-equivalent USD cost for today shown in the header.
- **7-day burn chart** - inline SVG bar chart of daily spend, last 7 days.
- **Prompt deck** - one button per prompt in webdash-prompts.json; clicking
  copies the prompt text to the clipboard with a flash confirmation.
- **Auto-poll** - page polls /api/state every 3s; shows a "disconnected"
  banner if the server stops responding.

## Install

```powershell
cd harness\web-dash
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Install copies three files into ~/.claude/ and seeds webdash-prompts.json
(only if it does not already exist). No changes to settings.json.

## Start / Stop

```powershell
# Foreground (Ctrl+C to stop)
powershell -File "$env:USERPROFILE\.claude\scripts\start-web-dash.ps1"

# Background (detached node process, PID saved to webdash.pid)
powershell -File "$env:USERPROFILE\.claude\scripts\start-web-dash.ps1" -Background

# Custom port
powershell -File "...start-web-dash.ps1" -Port 8080

# LAN mode (binds 0.0.0.0 instead of 127.0.0.1)
powershell -File "...start-web-dash.ps1" -Lan

# Stop background instance
powershell -File "$env:USERPROFILE\.claude\scripts\stop-web-dash.ps1"
```

Open: http://127.0.0.1:7777

## Prompt deck customisation

Edit `~\.claude\webdash-prompts.json` - array of {label, prompt} objects:

```json
[
  { "label": "Status report", "prompt": "Give me a status report: what you are doing, what is blocked, what is next." },
  { "label": "My custom prompt", "prompt": "Do something useful." }
]
```

## Uninstall

```powershell
.\uninstall.ps1
```

Removes server.js, start-web-dash.ps1, stop-web-dash.ps1, the webdash pid
file, and stops any running background instance. webdash-prompts.json is
NOT removed (user data) - delete it manually if desired.

## Ownership

Sentinel: mutwo:web-dash

Files owned (removed on uninstall):
- ~/.claude/scripts/webdash/server.js
- ~/.claude/scripts/start-web-dash.ps1
- ~/.claude/scripts/stop-web-dash.ps1
- ~/.claude/webdash.pid  (runtime, removed on uninstall/stop)

Files NOT owned (preserved on uninstall):
- ~/.claude/webdash-prompts.json  (user data, seeded once on first install)

No settings.json entries are added or removed by this mod.

## Security and cost notes

- Default bind is 127.0.0.1 (localhost only). The dashboard is
  unauthenticated; localhost-only is the only access control.
- The -Lan flag binds to 0.0.0.0, exposing the dashboard to your entire
  local network with no authentication. Use only on a trusted Wi-Fi network.
- Session cards display session summaries, which may contain code snippets,
  file paths, or other project details from your transcripts.
- Prompt deck v1 only copies prompts to the clipboard. Direct dispatch of
  prompts into Claude Code sessions is deferred pending the built-ins audit.
- Cost figures are API-equivalent estimates (same pricing table as the
  token-economy mod). On a subscription plan they represent value consumed
  against your rate limits, not a bill.
- The server caches the 7-day spend computation for 30 seconds to avoid
  repeatedly reading all transcript files on every poll.
