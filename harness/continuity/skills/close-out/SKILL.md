---
name: close-out
description: End-of-session housekeeping. Triggers on /close-out, "close out", "wrap up", "end the session", "document what we did", "before we stop", "let's wrap", "what needs documenting".
---

# Close-out

End-of-session housekeeping. Work through these steps in order; mark each with the outcome when done.

## Step 1 -- inventory

In a single parallel tool call batch, collect:

- `git status` and `git log --oneline -10` for each touched repo.
- List of existing docs: README.md, CLAUDE.md, LOG.md present in the cwd repo.

Print a short inventory (5-10 bullets). Move immediately to Step 2 without asking.

## Step 2 -- update existing docs

Apply updates to docs that **already exist** in the repo. Do not create new files uninvited.

| What to write | Where |
|---|---|
| Why a decision was made | LOG.md |
| Gotcha with symptom + fix | LOG.md |
| Durable project convention | CLAUDE.md |
| User-visible surface change | README.md |

Read all target files in one parallel batch, then apply all edits in one parallel batch. Do not preview individual entries; the Step 5 summary is the review.

Skip this step if no docs exist and there is nothing obvious to add.

## Step 3 -- memory writes (gated)

Propose any memories worth writing across sessions. Gate EVERY proposed memory write behind a single `AskUserQuestion` with `header: "Memory writes"` and `multiSelect: true`. One option per proposed memory; label is a short title; description says what it would say and its target file.

Question text: "Which of these memories should I write? (Each persists across all future sessions.)"

Wrong memories are a long-tail cost. If the user declines, do not write it, do not offer a smaller version. If zero memories are proposed, skip the gate entirely.

## Step 4 -- commit offer

Check git status. If there are uncommitted changes, offer to commit them. State the proposed commit message. Do not commit without the user's confirmation.

## Step 5 -- handoff offer

If work is unfinished (open blockers, in-flight branches, TODOs from Step 1), offer to write a handoff via the handoff skill. Say: "Want a handoff written to .claude/handoff.md for the next session?"

## Step 6 -- summary

Print a one-line summary of what changed:

> Closed out. Updated LOG.md (2 entries), saved 1 memory, committed. README unchanged.

## Rules

- No em-dashes. Use hyphens, colons, or parentheses.
- Do not ask "want me to apply this?" for LOG/CLAUDE/README edits -- just apply.
- Do not create LOG.md, CLAUDE.md, or README.md if they do not exist.
- Memory gate is mandatory for every proposed memory write. No exceptions except explicit "save this" / "remember this" from the user during the session.
