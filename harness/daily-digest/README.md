# daily-digest

A morning digest of Claude Code activity, generated locally from transcripts,
scheduled via Windows Task Scheduler. Optionally produces a spoken-word
narration and WAV audio via Windows SAPI -- no extra dependencies.

No data leaves your machine by default. Narration via `claude -p` is opt-in
and incurs a small API token cost (see below).

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

## Morning podcast mode

Three optional switches extend the digest with audio output:

| Switch | Effect |
|--------|--------|
| `-Narrate` | Generates `YYYY-MM-DD.narration.txt` -- a spoken-word version of the digest (150-250 words, second person, no markdown). Uses `claude -p` if the CLI is on PATH; falls back to a local markdown-strip if not. |
| `-Speak` | Implies `-Narrate`. Also renders `YYYY-MM-DD.wav` via Windows SAPI (`System.Speech`). No extra install; SAPI is built into Windows. |
| `-Play` | Implies `-Speak`. After writing the WAV, also plays it immediately through the default audio device. |

All narration/TTS steps are crash-proof: if SAPI or `claude -p` fail, a
warning goes to stderr and the script continues to exit 0. Safe for
unattended/scheduled runs.

### Token cost note

When `claude -p` is invoked (i.e., the claude CLI is on PATH and `-Narrate`
is used), one API call is made: input is roughly the digest text (~300-600
tokens), output is 150-250 words. At Sonnet rates this is approximately
$0.001-0.003 per run. The fallback (markdown-strip) costs nothing.

To force the local fallback (zero API cost), remove or rename `claude.cmd`
from your PATH before running.

## Install

```powershell
cd harness\daily-digest
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

The `-NoSchedule` switch copies the script only, skipping task registration:

```powershell
.\install.ps1 -Yes -NoSchedule
```

### Morning podcast scheduled task (opt-in)

Pass `-WithPodcast` to also register a second scheduled task
`mordor-morning-podcast` that runs `daily-digest.ps1 -Speak` every day at
07:30, producing the WAV before the 08:00 text digest:

```powershell
.\install.ps1 -Yes -WithPodcast
```

The plain `mordor-daily-digest` task at 08:00 is always registered (unless
`-NoSchedule`). The podcast task is strictly opt-in.

Registering tasks may require an elevated prompt on some policies. If
`schtasks /Create` fails, the installer prints the exact manual command to
run as Administrator and continues without failing.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes both scheduled tasks (`mordor-daily-digest` and
`mordor-morning-podcast`, each ignored if not found) and the copied script.
Generated digest and narration files in `~\.claude\digests\` are left
intact -- they are your data.

## Manual use

```powershell
# Today's digest (1-day lookback)
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1"

# Last 7 days
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -Days 7

# Custom output directory
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -OutDir C:\Reports

# Digest + narration text (uses claude -p if available, else local fallback)
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -Narrate

# Digest + narration text + WAV file (Windows SAPI, no install)
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -Speak

# Digest + narration + WAV + immediate playback
powershell -File "$env:USERPROFILE\.claude\scripts\daily-digest.ps1" -Play
```

The script prints the output file path(s) on success: the markdown digest
path, then the narration path (if -Narrate), then the WAV path (if -Speak).

## Ownership

This mod owns exactly:

- `~\.claude\scripts\daily-digest.ps1` -- the runtime script (removed by uninstall)
- Windows Task Scheduler task `mordor-daily-digest` (removed by uninstall)
- Windows Task Scheduler task `mordor-morning-podcast` (removed by uninstall if present)

The task names `mordor-daily-digest` and `mordor-morning-podcast` are the
sentinels. The mod does NOT touch `~\.claude\settings.json`.

## TTS / SAPI note

Speech synthesis uses `System.Speech.Synthesis.SpeechSynthesizer` from the
.NET Framework, which ships with Windows. No NuGet packages, no extra install.
The voice used is the Windows default TTS voice (configurable in Settings >
Time & Language > Speech). WAV output is uncompressed PCM; file size is
typically 1-3 MB for a 150-250 word narration.

## Pricing note

Token costs in the digest are API-equivalent estimates using the same embedded
price table as the `token-economy` mod. On a subscription plan these reflect
value consumed against your rate limits, not a bill. For exact, maintained
figures use: `npx ccusage`
