---
name: scribe
description: Capture hard-won lessons from this session as path-scoped project rules. Triggers on /scribe, "scribe", "record what we learned", "save this lesson", "write a rule for this".
---

# Scribe

Distill durable, non-obvious lessons from this session into path-scoped rules
that auto-load in future sessions when matching files are edited.

## What makes a good rule

- **Specific** -- names a concrete gotcha, pattern, or constraint.
- **Falsifiable** -- another agent could check whether it was followed.
- **Path-tied** -- the lesson is only relevant when certain file types or
  directories are in play. A rule for `**/*.ps1` should not appear when
  editing a Python file.

## Do NOT scribe

- Task status or completion notes (belongs in handoff or LOG.md, not rules).
- Secrets, tokens, or credentials.
- Anything already documented in CLAUDE.md or an existing rule file.
- Transient state that is true only during this session.
- Anything already in git history as a documented convention.

---

## Procedure

### Step 1 -- reflect

Review the session: what gotchas were hit, what conventions were discovered,
what mistakes were corrected that the next agent should not repeat?

Filter hard: only durable, non-obvious lessons qualify. Skip task status,
skip things already documented, skip obvious language conventions.

### Step 2 -- propose

For each lesson, draft a rule with three parts:

1. **Glob** -- the path pattern where the rule applies (e.g. `**/*.ps1`,
   `harness/**`, `**/*.md`). Prefer the narrowest glob that is still
   meaningful.
2. **Title** -- a short imperative phrase (5-10 words).
3. **Guidance** -- 1-4 lines. Describe the constraint or pattern precisely.
   Include the symptom or failure mode that motivated it when useful.

Group related lessons by topic (e.g. "powershell-quirks", "hook-contract",
"json-serialization"). Each topic maps to one rule file.

If no lessons qualify, say so and stop -- do not write empty files.

### Step 3 -- gate (mandatory)

Fire `AskUserQuestion` with:

- `header`: "Which lessons should become rules?"
- `multiSelect`: true
- One option per proposed rule. Label = rule title. Description = the
  glob and one-sentence summary of the guidance.

**Never write any rule file without the user approving it here.**
If the user approves none, confirm and stop.

### Step 4 -- write

For each approved rule:

1. Determine the topic slug (kebab-case, e.g. `powershell-quirks`).
2. Target file: `<repo-root>\.claude\rules\<topic>.md`
   where `<repo-root>` is the cwd (or the root of the current git repo if
   the cwd is a subdirectory).
3. If the file does not exist, create it with this structure:

   ```
   ---
   paths:
     - <glob>
   ---

   ## <Title>

   <Guidance>
   ```

4. If the file already exists, append a new section:

   ```

   ## <Title>

   <Guidance>
   ```

   Also merge the glob into the existing `paths:` frontmatter list if it
   is not already present (add it as a new `  - <glob>` line under
   `paths:`).

5. Create `<repo-root>\.claude\rules\` if it does not exist.

### Step 5 -- confirm

List every file written and the rule titles added. Remind the user:

> Rules in .claude/rules/ auto-load when matching files are edited --
> no CLAUDE.md edits needed.

---

## Notes

- Rules are project-scoped (live in the repo's `.claude/rules/`), not
  global. They do not go in `~\.claude\`.
- If close-out is installed, run /scribe as the "what did we learn" step
  before or after /close-out -- the two skills complement each other.
  close-out handles docs and memory; scribe handles reusable path-scoped
  rules.
