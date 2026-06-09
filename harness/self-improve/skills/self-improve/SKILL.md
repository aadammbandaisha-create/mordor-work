---
name: self-improve
description: scan recent sessions for friction and propose harness improvements
triggers:
  - /self-improve
  - improve the harness
  - what is causing friction
  - tune the harness
---

# self-improve skill

Analyze recent Claude Code session transcripts for friction patterns and
propose concrete harness improvements. Never auto-apply changes.

## Repo contract (inline reference)

- Every mod lives at harness/<name>/ with README.md, install.ps1, uninstall.ps1.
- Installers: -Yes switch for unattended; Read-Host confirm otherwise; JSON validate before+after; timestamped .bak backup; restore on failure.
- Every entry added to settings.json embeds sentinel mutwo:<mod-name>; uninstall removes only owned entries.
- PowerShell 5.1 syntax only; ASCII-only content; all files -Encoding UTF8; always exit 0 in hook scripts.
- Runtime hooks: $ErrorActionPreference = "SilentlyContinue"; never write stdout noise from hooks.

## Procedure

### Step 1 - run the scanner

Run the friction scanner using the path relative to this skill file:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\friction-scan.ps1" -Days 7
```

`<skill-dir>` is the directory that contains this SKILL.md file, typically:
`%USERPROFILE%\.claude\skills\self-improve`

Capture the JSON output. If `{"error":...}` is returned, report the error
to the user and stop.

### Step 2 - interpret the signals

Read the JSON object:

- `permissionDenials.count` - how many times the auto-mode classifier blocked
  an action. Review `examples` to find patterns (same tool? same operation
  category?). More than 3-5 per session = systemic; 1-2 = one-off.
- `toolErrors.topPatterns` - recurring tool failures. A pattern appearing
  3+ times suggests a missing dependency, wrong path, or a needed permission
  allow-rule.
- `apiRetries` - network or rate-limit hits. More than a handful suggests
  a context / model configuration issue.
- `longSessions` - sessions whose transcript exceeded 4 MB. Each one is a
  compaction-pressure event. Recurring long sessions suggest tasks that should
  be split or that need a /compact habit reminder.
- `bashCommandTop` - the 10 most-used shell commands. Recurring commands that
  are not in settings.json permissions.allow are allowlist candidates.

Distinguish systemic (pattern across multiple sessions) from one-off (single
session anomaly). Only systemic signals justify a proposal.

### Step 3 - propose at most 3 improvements

Rank by impact / effort. For each:

1. State the signal that justifies it (count, pattern text, or example).
2. Describe the concrete change:
   - New mod: name, what it does, which files it ships, what sentinel it uses.
   - Permission allow-rule: the exact string to add to settings.json
     `permissions.allow`.
   - Hook tweak: which hook event, what command, what sentinel.
3. Estimate effort: low (settings.json one-liner), medium (new script),
   high (full new mod with installer).

### Step 4 - gate via user confirmation

Use AskUserQuestion (or equivalent interactive gate) to ask:

  "I found [N] friction signals. Shall I build [top proposal]? (yes / no /
  show all)"

Do not create any file until the user says yes to a specific proposal.

### Step 5 - build approved mods in the repo

If the user approves a new mod:

- Create harness/<name>/ following the repo contract above.
- Ship README.md, install.ps1, uninstall.ps1.
- If the mod adds hooks, copy the hook helpers verbatim from
  harness/windows-state-indicator/install.ps1:
  Read-Settings, Ensure-PropertyObject, Remove-OwnedEntries,
  New-HookEntry, Set-HookEvent.
- Sentinel string: mutwo:<name> embedded in every owned settings.json entry.

If the user approves a permission allow-rule, show the exact JSON diff first:

```
Before:  "permissions": { "allow": [...] }
After:   "permissions": { "allow": [..., "<new-rule>"] }
```

Then ask for final confirmation before writing.

### Never

- Never edit settings.json without showing the exact diff and receiving
  explicit confirmation.
- Never run install.ps1 automatically; always ask the user to run it.
- Never propose more than 3 improvements per invocation.
