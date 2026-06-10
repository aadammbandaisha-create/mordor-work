# Making the harness smarter — agreed ideas (June 9, 2026)

The model is fixed, so "smarter" means improving: what Claude knows when it
decides, what feedback it gets while working, what gate it passes before
claiming done, and what it retains afterward. Ranked by quality-gained-per-token.

## 1. check-on-edit (build first)

PostToolUse hook after Edit/Write that runs the project's cheap fast checks
(tsc on the touched file, ruff lint, PSScriptAnalyzer) and on failure exits 2
with the error text, so Claude sees the type/lint error on the very next turn.
Sibling of format-on-edit (its README already sketches this as the "strict
variant"). Constraint: strictly informational — feeds back via exit 2 but never
blocks or fails the edit itself (keeps Phase-1 "log-only guards" spirit).
Near-zero token cost; errors caught one edit late cost one fix.

## 2. scribe / learned rules (build second — the only one that compounds)

Wire a "what did this session learn the hard way?" step into the existing
/close-out skill. Lessons are written as path-scoped rules
(`.claude/rules/*.md` with `paths:` frontmatter) so they auto-load only when
relevant files are touched, instead of bloating CLAUDE.md. Proof of need: the
PS 5.1 UTF-8 and `cmd /c` gotchas had to be hand-recorded in
docs/harness-structure.md. Session 50 should start smarter than session 1.

## 3. review-gate (/ship)

Before work is declared done, diff the branch; if the diff crosses a threshold
(size, or touches load-bearing paths), spawn the reviewer role (Opus 4.8)
adversarially with the diff + original acceptance criteria. Small diffs skip
the gate. Expensive — earns its cost only on work that matters, per the
tiering doctrine.

## 4. continuity v2 — richer session-start context

Additions to the SessionStart injection: failing-test summary, TODO/FIXME
deltas on the branch, and a cached project map (one-time generated repo
summary: key dirs, entry points, conventions) injected instead of Claude
re-scouting the codebase each session.

## Explicitly rejected

- Model-knob mods — the escalation ladder already covers it.
- Anything duplicating built-ins (plan mode, /code-review, claude agents) —
  see docs/builtins-audit.md, which already killed four mods this way.
- Multi-agent debate/consensus — token bonfires, marginal gain for solo work.
