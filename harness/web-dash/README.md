# web-dash

A local web dashboard and command deck for Claude Code on Windows. Shows
active session state, context usage, 7-day spend, and a prompt deck, and can
DISPATCH headless Claude Code runs from the browser. Single Node 24 HTTP
server, zero npm dependencies.

## What it does

- **Session cards** - lists all sessions updated in the last 24h with state
  dot (working/idle), project title, summary, and age.
- **Context gauge** - horizontal bar showing context window % for the newest
  session (computed from its transcript; thresholds 60%=yellow, 80%=red).
- **Today spend** - API-equivalent USD cost for today shown in the header.
- **7-day burn chart** - inline SVG bar chart of daily spend, last 7 days.
- **Command deck** - project selector, free-text prompt box, and one button
  pair (copy / run) per prompt in webdash-prompts.json. "Copy" copies to
  clipboard; "Run" dispatches a headless Claude Code run.
- **Jobs panel** - shows dispatched runs with status chip (running=amber
  pulse, done=green, error/killed=red), prompt snippet, project, age,
  expandable output tail, and a Kill button on running jobs.
- **Auto-poll** - page polls /api/state every 3s; polls /api/jobs every 3s
  while any job is running or just after a dispatch.

## Install

```powershell
cd harness\web-dash
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Install copies three files into ~/.claude/ and seeds webdash-prompts.json and
webdash-projects.json (only if they do not already exist). No changes to
settings.json.

## Start / Stop

```powershell
# Foreground (Ctrl+C to stop)
powershell -File "$env:USERPROFILE\.claude\scripts\start-web-dash.ps1"

# Background (detached node process, PID saved to webdash.pid)
powershell -File "$env:USERPROFILE\.claude\scripts\start-web-dash.ps1" -Background

# Custom port
powershell -File "...start-web-dash.ps1" -Port 8080

# LAN mode (binds 0.0.0.0; prints token; dispatch requires token from non-loopback)
powershell -File "...start-web-dash.ps1" -Lan

# Stop background instance
powershell -File "$env:USERPROFILE\.claude\scripts\stop-web-dash.ps1"
```

Open: http://127.0.0.1:7777

## Prompt deck customisation

Edit `~\.claude\webdash-prompts.json` - array of {label, prompt} objects:

```json
[
  { "label": "Status report", "prompt": "Give me a status report: ..." },
  { "label": "My custom prompt", "prompt": "Do something useful." }
]
```

## Project allowlist

Edit `~\.claude\webdash-projects.json` - array of {label, path} objects.
Only paths listed here can be used as the cwd for dispatched runs. The client
selects a project by index; path strings are never accepted from the client.

```json
[
  { "label": "mordor harness", "path": "C:\\Users\\qq\\Desktop\\mutwo-windows-claude-harness" },
  { "label": "my other project", "path": "C:\\Users\\qq\\code\\myproject" }
]
```

## API endpoints

| Method | Path                     | Auth required | Description                       |
|--------|--------------------------|---------------|-----------------------------------|
| GET    | /                        | no            | Dashboard HTML page               |
| GET    | /api/state               | no            | Sessions, context, spend, prompts, projects |
| POST   | /api/dispatch            | yes*          | Spawn a headless Claude Code run  |
| GET    | /api/jobs                | no            | List all in-memory jobs           |
| POST   | /api/jobs/<id>/kill      | yes*          | Kill a running job (taskkill /T)  |

*Token is required from non-loopback addresses. Localhost is always trusted.

### POST /api/dispatch

Request body (JSON):
```json
{ "prompt": "...", "projectIndex": 0 }
```

- `prompt`: non-empty string, max 4000 characters.
- `projectIndex`: integer index into webdash-projects.json.

Response `200 {"id": "<hex>"}` on acceptance. Poll /api/jobs for status.

### GET /api/jobs

Returns `{"jobs": [...]}` newest first. Each job:
```json
{
  "id": "...",
  "prompt": "first 200 chars",
  "project": {"label": "...", "path": "..."},
  "status": "running|done|error|killed",
  "startedAt": "ISO",
  "endedAt": "ISO or null",
  "exitCode": 0,
  "output": "last 16KB of stdout+stderr"
}
```

## WEBDASH_CLAUDE_EXE override

Set the environment variable `WEBDASH_CLAUDE_EXE` before starting the server
to substitute a different executable for dispatch. This is intended for
testing (point at a stub that exits 0) and for environments where the Claude
binary is installed at a non-default location.

Default: `C:\Users\qq\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe`

For test stubs on Windows (where `.js` files require the Node host), also set
`WEBDASH_CLAUDE_ARGS_PRE` to a JSON array of args prepended before the fixed
`[-p, prompt, --output-format, text]` args. Example:

```
WEBDASH_CLAUDE_EXE=node
WEBDASH_CLAUDE_ARGS_PRE=["C:\\path\\to\\stub.js"]
```

`WEBDASH_CLAUDE_ARGS_PRE` is ignored in normal operation (leave unset).

## Uninstall

```powershell
.\uninstall.ps1
```

Removes server.js, start-web-dash.ps1, stop-web-dash.ps1, the webdash pid
file, and stops any running background instance. The following user-data files
are NOT removed - delete them manually if desired:
- webdash-prompts.json
- webdash-projects.json
- webdash-token
- webdash-jobs.log

## Ownership

Sentinel: mordor:web-dash

Files owned (removed on uninstall):
- ~/.claude/scripts/webdash/server.js
- ~/.claude/scripts/start-web-dash.ps1
- ~/.claude/scripts/stop-web-dash.ps1
- ~/.claude/webdash.pid  (runtime, removed on uninstall/stop)

Files NOT owned (preserved on uninstall):
- ~/.claude/webdash-prompts.json  (user data, seeded once on first install)
- ~/.claude/webdash-projects.json (user data, seeded once on first install)
- ~/.claude/webdash-token         (auth token, created by start script)
- ~/.claude/webdash-jobs.log      (append-only audit log of all dispatched jobs)

No settings.json entries are added or removed by this mod.

## Security

**Dispatch = arbitrary prompt execution.** When a run is dispatched, the
server spawns a real Claude Code process with the given prompt under the
user's Claude credentials. Treat this endpoint with the same care as shell
access.

**Localhost is trusted.** Any request from 127.0.0.1 or ::1 can call POST
endpoints without a token. The browser on the same machine is always trusted.

**LAN mode requires a token.** When `-Lan` is passed, the server binds to
0.0.0.0. Requests from non-loopback addresses must supply the token via the
`x-webdash-token` header or `?token=` query parameter. The token is a random
GUID stored in `~/.claude/webdash-token` and printed to the console when -Lan
is active. The UI prompts for it on the first 401 and caches it in
localStorage.

**The project allowlist limits blast radius.** Dispatch only accepts a
project index, not a free-form path. The cwd is resolved server-side from the
allowlist, so a compromised token cannot direct runs to arbitrary directories.

**Jobs are audited.** Every job that reaches a terminal state (done, error,
killed) is appended as a JSON line to `~/.claude/webdash-jobs.log`. The token
value is never written to logs or responses.

**The Claude binary is invoked directly with an args array and shell:false**
to prevent command injection via crafted prompt strings.

## Cost notes

- Cost figures are API-equivalent estimates (same pricing table as the
  token-economy mod). On a subscription plan they represent value consumed
  against your rate limits, not a bill.
- The server caches the 7-day spend computation for 30 seconds to avoid
  repeatedly reading all transcript files on every poll.
- Dispatched runs consume real Claude credits / plan quota.
