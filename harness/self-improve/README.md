# self-improve

Analyze recent Claude Code session transcripts for friction patterns and
propose concrete harness improvements. Proposals are never auto-applied.

## What it does

1. The friction scanner (`scripts/friction-scan.ps1`) reads `~\.claude\projects\**\*.jsonl`
   files modified within a rolling window (default: last 7 days). It streams
   each file line-by-line (no full-file load) and counts:

   - **Permission denials** - lines containing the auto-mode classifier denial
     message or "doesn't want to proceed". High counts are allowlist candidates.
   - **Tool errors** - `"is_error":true` entries, grouped by the first 60 chars
     of error text. Recurring patterns reveal missing deps or wrong paths.
   - **API retries** - "API Error" or "overloaded_error" hits. Proxy for
     rate-limit or context-size pressure.
   - **Long sessions** - transcript files over 4 MB. Proxy for compaction
     pressure; each is a session that ran long enough to risk auto-compaction.
   - **Top shell commands** - the 10 most-invoked Bash/PowerShell first tokens,
     which are allowlist candidates if they appear frequently without a
     permissions.allow entry.

   Output is a single JSON object on stdout. Always exits 0.

2. The `SKILL.md` skill (`/self-improve`) orchestrates the full flow:
   runs the scanner, interprets signals (systemic vs. one-off), proposes at
   most 3 ranked improvements, gates on user confirmation via AskUserQuestion,
   and builds approved mods in the repo following the harness contract. It
   never edits settings.json without showing an exact diff and receiving
   explicit confirmation.

## Install

```powershell
cd harness\self-improve
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Copies `skills\self-improve\` (SKILL.md + scripts\friction-scan.ps1) to
`~\.claude\skills\self-improve\`. No changes to settings.json.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes `~\.claude\skills\self-improve\` entirely.

## Ownership

This mod owns exactly:

- `~\.claude\skills\self-improve\SKILL.md`
- `~\.claude\skills\self-improve\scripts\friction-scan.ps1`

No sentinel string in settings.json is needed because this mod does not touch
settings.json. Uninstall removes only the above files.

## Usage

Invoke the skill inside a Claude Code session:

```
/self-improve
```

or say "improve the harness" / "what is causing friction" / "tune the harness".

Run the scanner standalone:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude\skills\self-improve\scripts\friction-scan.ps1" -Days 7
```

## Security and cost notes

- The scanner is read-only. It never writes to any file; it never reads
  credentials or API keys. Transcript files contain conversation history
  which may include tool outputs - the scanner only extracts counts and
  short text snippets (first 80 chars of denial messages, first 60 chars of
  error text).
- The skill invokes the scanner as a subprocess; the JSON output is small
  and bounded regardless of transcript volume.
- Cost: the scanner itself is free (local PowerShell). The skill interpretation
  step uses model tokens proportional to the JSON summary, not to transcript
  size.
