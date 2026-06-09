# daily-digest

A morning digest of Claude Code activity, generated locally from transcripts,
scheduled via Windows Task Scheduler.

No data leaves your machine. No AI calls are made. Everything is read from the
JSONL transcript files Claude Code writes under `~\.claude\projects\`.

## What it does

Scans `~\.claude\projects\**\*.jsonl` files modified within the lookback window
and writes a Markdown digest to `~\.claude\digests\YYYY-MM-DD.md`.

Each digest contains:

- A per-project section showing: session count, total in/out tokens, estimated
  API-equivalent cost, and the last assistant message (first 300 chars) for each
  session in the window.
- A totals footer with tokens broken down by model family and estimated cost.
- A "yesterday vs today" cost one-liner when both days' digest files exist.

The script is also safe to run manually at any time with any `-Days` value.

## Install

```powershell
cd harness\daily-digest
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

The `-NoSchedule` switch copies the script only, skipping task registration
(useful if you prefer to trigger the digest manually or via your own scheduler):

```powershell
.\install.ps1 -Yes -NoSchedule
```

Registering the task may require an elevated prompt on some policies. If
`schtasks /Create` fails, the installer prints the exact manual command to run
as Administrator and continues without failing.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes the scheduled task and the copied script. Generated digest files in
`~\.claude\digests\` are left intact - they are your data.

## Manual use

```powershell
# Today's digest (1-day lookback)
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1"

# Last 7 days
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -Days 7

# Custom output directory
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -OutDir C:\Reports
```

The script prints the output file path on success.

## Ownership

This mod owns exactly:

- `~\.claude\scripts\daily-digest.ps1` - the runtime script (removed by uninstall)
- Windows Task Scheduler task named `mutwo-daily-digest` (removed by uninstall)

The task name `mutwo-daily-digest` is the sentinel. The mod does NOT touch
`~\.claude\settings.json`.

## Pricing note

Token costs are API-equivalent estimates using the same embedded price table as
the `token-economy` mod. On a subscription plan these reflect value consumed
against your rate limits, not a bill. For exact, maintained figures use:
`npx ccusage`

## Future work (v2)

A `-Narrative` switch could pipe the digest into `claude -p` to produce a
plain-English summary paragraph. Intentionally absent in v1 to keep the
script free of network calls and AI cost. The digest Markdown is structured
so a `claude -p` pipeline can consume it directly when added.
