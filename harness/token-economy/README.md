# token-economy

Token-usage visibility and conservation for Claude Code on Windows.

Running out of tokens silently is the failure mode this mod removes. You
cannot conserve what you cannot see.

## What it installs

1. **Statusline** (`statusLine` in `~\.claude\settings.json`):

   ```text
   Sonnet | ctx 42% (84k/200k) | $1.23 | git:main
   ```

   - **Context %** — the highest-signal number in Claude Code. Past ~80%
     the line turns red and shows `COMPACT SOON`: compact deliberately at a
     natural breakpoint instead of getting auto-compacted mid-task (which
     burns tokens re-establishing context and degrades output quality).
   - **Session cost** — API-equivalent dollars for the current session.
   - Model name and git branch.

2. **Usage report** (`~\.claude\scripts\usage-report.ps1`):

   ```powershell
   powershell -File "$env:USERPROFILE\.claude\scripts\usage-report.ps1" -Days 7
   ```

   Aggregates all local transcripts into tokens-by-day and tokens-by-model
   with estimated API-equivalent cost. For exact, maintained pricing use
   `npx ccusage` (Node is required; the report works without it).

## Conservation playbook

These habits save more than any tooling. Ordered by impact:

1. **Tier your models: smart director, cheap workers.** The main agent
   that plans and directs should be the strong model; subagents doing
   mechanical work (searching, formatting, bulk edits) should be cheaper
   ones. Configured in `~\.claude\settings.json`:

   ```json
   {
     "model": "claude-fable-5",
     "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" }
   }
   ```

   Custom agents in `.claude/agents/*.md` can pin `model: haiku` in their
   frontmatter for true grunt work. Switch the main model mid-session with
   `/model` when a task needs more or less brainpower.
2. **`/clear` between unrelated tasks.** Carrying a finished task's context
   into the next one means every subsequent message re-reads it (and
   re-bills it on cache misses).
3. **Compact deliberately, not automatically.** When the statusline warns,
   finish the current step, then `/compact` with a hint about what to keep.
   Auto-compaction at 95% picks what survives without your input.
4. **Don't paste what Claude can read.** Reference files by path instead of
   pasting their contents — pasted text lives in context forever; a Read
   happens once and can fall out during compaction.
5. **Keep CLAUDE.md lean (< 200 lines).** It is re-sent with every session.
   Use path-scoped rules (`.claude/rules/*.md` with `paths:` frontmatter)
   so instructions load only when relevant files are touched.
6. **Watch subagent fan-out.** Each subagent is a fresh context paying its
   own way. Parallel agents are powerful but they multiply spend.
7. **Plan mode for big tasks.** Iterating on a plan is cheap; iterating on
   wrong implementations is not.

## Install

```powershell
cd harness\token-economy
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code to activate the statusline.

## Uninstall

```powershell
.\uninstall.ps1
```

## Ownership

The statusline command embeds the sentinel `mutwo:token-economy` (as an
inert trailing argument). Install replaces only a statusline it owns
(warning if it overwrites a foreign one — recoverable from the timestamped
backup), and uninstall removes only an owned entry.

## Notes

- Context % is computed from the last main-chain assistant message's
  `usage` fields in the session transcript, against a 200k window.
- Cost figures on a subscription plan are API-equivalent value consumed
  against your rate limits, not a bill.
