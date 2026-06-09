# visual-verify

A Claude Code skill that gives sessions a "see what you built" loop for
web UI work. The agent drives a real browser, captures screenshots, reads
them with multimodal vision, and iterates until the UI matches the intent.

## Why CLI instead of the Playwright MCP

The Playwright MCP works by streaming the full accessibility tree of every
page into context. That is convenient but expensive: on a typical SPA the
tree runs 2000-5000 tokens per snapshot, and a five-step verify loop can
burn 15k-25k tokens just in tree overhead before any screenshot is even
considered. The skill uses `npx playwright` (the project-local CLI) and
`page.screenshot()` instead. A full-page PNG read via Claude Code's
multimodal Read is a single tool call; console output is a few hundred
bytes of plain text. End-to-end cost for a three-step loop: ~1k-3k tokens.
The CLI approach is roughly 4x cheaper for routine UI verification.

## What the skill does

1. Checks that Playwright is installed locally. If not, tells the user
   the exact install commands and stops -- it never installs unprompted.
2. Determines the target URL (from the user, from a running dev server, or
   by inferring the default port from framework config).
3. Writes a minimal one-off driver script under `.claude/screenshots/`,
   runs it with `node`, captures browser console output alongside the
   screenshot, and reads the PNG.
4. Evaluates visual appearance AND console errors. A clean screenshot with
   `[pageerror]` lines is not a pass.
5. Iterates -- fixes code, increments the step name, re-runs -- up to five
   times before asking the user for guidance.
6. Adds a mobile viewport pass (390x844) when the change touches
   responsive layout.
7. On wrap-up: reports what was verified, kills any dev server it started,
   and offers to add `.claude/screenshots/` to `.gitignore`.

## Trigger phrases

- `/visual-verify`
- "see what you built"
- "screenshot the app"
- "verify the UI visually"
- "does it look right"

## Install

```powershell
cd harness\visual-verify
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code (or start a new session) to load the skill.

## Uninstall

```powershell
.\uninstall.ps1
```

## Ownership

This mod owns exactly one directory:

```
~\.claude\skills\visual-verify\
```

Install copies `SKILL.md` into that directory and creates it if absent.
Uninstall removes the entire directory and nothing else. No
`settings.json` entries are written.

## Security note

The driver script written to `.claude/screenshots/_drive.js` is
disposable and regenerated on every iteration. It runs under `node` with
the permissions of the current user. It navigates only to the URL
determined in Step 2 of the skill. Do not commit `.claude/screenshots/`
to source control -- the skill offers to add it to `.gitignore`.

## Cost note

The skill itself adds one SKILL.md to the agent-list (a one-line
description shown to the director). Cost is zero until the skill is
invoked. Each invocation: ~1k-3k tokens for a three-step loop via the
CLI path, versus ~12k-25k tokens via the Playwright MCP accessibility-tree
path.
