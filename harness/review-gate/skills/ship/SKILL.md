---
name: ship
description: Review-gate the current changes before declaring done -- diffs the branch and runs an adversarial Opus review on substantial changes. Triggers on /ship, "ship it", "ready to ship", "review before commit", "review-gate".
---

# Ship

Adversarial review gate before work is declared done. Not a commit trigger --
the human commits. This gate only decides whether the work is ready.

## Step 1 -- compute the diff

Get the merge-base with the default branch (try `main` then `master` then
`develop`), then run these two commands:

```powershell
$base = git merge-base HEAD main 2>$null
if (-not $base) { $base = git merge-base HEAD master 2>$null }
if (-not $base) { $base = 'HEAD' }
git diff --stat $base
git diff $base
```

Note: bash subshell syntax (`$(...)`) and pipeline chaining (`||`) are not
available in PowerShell 5.1. Use the explicit variable form above.

If there is no branch divergence (all changes are uncommitted working-tree
edits), use `git diff` (working tree vs index+HEAD) and `git diff --stat`.

Collect:
- Total added + removed lines from `git diff --stat` (the summary line).
- The full unified diff text.
- The list of changed file paths.

## Step 2 -- threshold check (cheap path)

**Threshold: 40 total changed lines.**

Load-bearing paths that bypass the threshold (gate runs regardless of size):
- Any file named `install.ps1` or `uninstall.ps1`
- Any file matching `*.config`, `*.json`, `*.yaml`, `*.yml`
- Any path containing the words `auth`, `security`, `secret`, `token`, `key`,
  `credential`, or `password` (case-insensitive)
- Any CI/CD file (`.github/`, `Makefile`, `Dockerfile`, `*.ci.*`)
- `settings.json` anywhere

**If total changed lines < 40 AND no load-bearing path is touched:**

Report exactly:

> small change -- gate skipped (N lines changed, no load-bearing paths).
> All clear to commit.

Stop. Do not spawn the reviewer.

**Rationale:** Opus 4.8 reviewer tokens are expensive. Sub-40-line diffs with
no structural or security surface rarely contain the class of bugs that
adversarial review catches. This threshold is conservative by design -- when
in doubt, it falls through to review.

## Step 3 -- spawn the reviewer (substantial diff path)

Spawn a subagent with the `reviewer` role (Opus 4.8) using the Agent tool.
The brief must be self-contained -- the reviewer has no session context.

Brief template:

```
You are an adversarial code reviewer. Your job is to find real problems, not
to praise the work. Be terse. Every finding must cite a specific file+line or
code fragment.

## Diff under review
<paste full unified diff here>

## Context
Session intent / acceptance criteria (from the user's request, if known):
<paste the session goal here, or "not provided">

## Your task
Review for:
1. Correctness bugs -- logic errors, off-by-one, wrong conditions, unhandled
   edge cases, broken control flow.
2. Regressions -- anything this change could break in code NOT shown in the
   diff (call it out by name; do not make up callers that may not exist).
3. Contract violations -- does this satisfy the acceptance criteria? Are there
   missing pieces?
4. Security issues -- injection, path traversal, credential exposure, unsafe
   deserialization, privilege escalation.

Severity labels: CRITICAL (ship-blocker), MAJOR (should fix before commit),
MINOR (nice to fix), NITS (style, optional).

Format: one finding per bullet. Severity label in brackets. File:line cited.
If you find nothing, say "LGTM -- no findings." Do not pad.
```

## Step 4 -- present findings

Display the reviewer's output in full.

**If there are CRITICAL or MAJOR findings:**

> Review found issues that should be fixed before committing.
> Want me to fix [list the critical/major findings briefly]?

Offer to fix each finding. Do not auto-fix without confirmation.

**If findings are MINOR or NITS only, or LGTM:**

> Review passed. No blockers found. Clear to commit.

Optionally note any MINOR/NIT items inline.

## Rules

- NEVER auto-commit. The human always commits.
- Do not summarize or paraphrase the reviewer's output -- print it in full.
- This skill complements (does not replace) the built-in /code-review skill.
  Use /code-review for a deeper multi-pass review when needed.
- If `git` is not available or the diff fails, report the error and stop;
  do not proceed with an empty diff.
- If the session intent is unknown, pass "not provided" -- do not fabricate
  acceptance criteria.
