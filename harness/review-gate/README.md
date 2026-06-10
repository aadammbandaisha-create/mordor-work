# review-gate

Adversarial review gate for Claude Code on Windows. Invoke `/ship` before
declaring work done -- the skill diffs the current branch, checks whether the
change is large enough to warrant a review, and if so spawns an Opus 4.8
subagent to find correctness bugs, regressions, and contract violations.

## What it installs

**ship skill** -- `~\.claude\skills\ship\SKILL.md`

Invoke `/ship` (or say "ship it", "ready to ship", "review before commit",
"review-gate") to run the gate.

### Procedure

1. **Diff** -- computes `git diff --stat` and `git diff` against the
   merge-base with the default branch (or working-tree diff when there is no
   branch divergence).

2. **Threshold check (cheap path)** -- if total changed lines < 40 AND no
   load-bearing path is touched, the gate is skipped and the change is cleared
   immediately. No Opus tokens consumed.

   Load-bearing paths that bypass the threshold regardless of size:
   - `install.ps1`, `uninstall.ps1`
   - `*.config`, `*.json`, `*.yaml`, `*.yml`
   - Paths containing `auth`, `security`, `secret`, `token`, `key`,
     `credential`, or `password`
   - CI/CD files (`.github/`, `Makefile`, `Dockerfile`)
   - `settings.json` anywhere

   **Rationale:** Opus reviews are expensive. Sub-40-line diffs with no
   structural or security surface rarely contain the bugs adversarial review
   catches. The threshold is conservative -- when in doubt, the gate runs.

3. **Reviewer subagent** -- for substantial diffs, spawns the `reviewer`
   role (Opus 4.8) via the Agent tool with the full unified diff and the
   session's acceptance criteria. The reviewer returns severity-ranked
   findings: CRITICAL, MAJOR, MINOR, NITS, or LGTM.

4. **Findings** -- displayed in full. If CRITICAL or MAJOR findings exist,
   the skill recommends fixing before commit and offers to apply fixes. If
   clean or NITS only, it gives an explicit green light.

5. **No auto-commit** -- the human always commits. This skill never touches
   the index or creates commits.

## Install

```powershell
cd harness\review-gate
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

## Uninstall

```powershell
cd harness\review-gate
.\uninstall.ps1
```

## Ownership

| Owned item | What it is |
|---|---|
| `~\.claude\skills\ship\` | skill directory (entire dir) |

Uninstall removes only the above. No hooks, no settings.json changes.

## Cost note

Opus 4.8 tokens are only consumed when the diff exceeds the threshold (40
lines or load-bearing path). Small mechanical changes clear the gate instantly
at zero Opus cost. A typical review of a 200-line diff costs on the order of
a few cents at API rates.

## Complements /code-review

`/ship` and `/code-review` serve different moments:

- `/ship` -- quick pre-commit gate, structured severity output, fires on your
  signal ("I think this is done").
- `/code-review` -- deeper multi-pass review you can run at any point,
  supports `--comment` for inline PR comments and `--fix` to auto-apply.

Use both when quality matters most.
