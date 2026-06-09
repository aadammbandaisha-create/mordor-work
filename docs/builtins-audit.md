# Built-ins audit (Claude Code v2.1.170, Windows 11)

## Summary table

| Feature | Available on this setup | Confidence | Enable command |
|---|---|---|---|
| Remote Control | YES | High (confirmed from primary doc) | `claude --remote-control` or `claude remote-control` |
| Dispatch | REQUIRES Claude Desktop app (separate install) | High (confirmed from primary doc) | Install Desktop app, open Cowork tab, click Dispatch |
| Background agents (`claude agents`) | YES | High (confirmed from primary doc, v2.1.139+ required; v2.1.170 qualifies) | `claude agents` |
| Voice mode | YES | High (confirmed from primary doc, Windows native audio module confirmed) | `/voice` inside a session |
| Channels (Telegram/Discord) | YES with conditions (Bun required) | High (confirmed from primary doc; no Windows exclusion) | `/plugin install telegram@claude-plugins-official` then `claude --channels plugin:telegram@claude-plugins-official` |
| Cloud Routines (`/schedule`) | YES | High (confirmed from primary doc, v2.1.81+ required; v2.1.170 qualifies) | `/schedule` inside a session or `claude.ai/code/routines` |
| Desktop Scheduled Tasks | REQUIRES Claude Desktop app (separate install) | High (confirmed from primary doc) | Install Desktop app, Routines sidebar, New routine, choose Local |
| `/loop` (session-scoped scheduling) | YES | High (confirmed from primary doc, v2.1.72+ required; v2.1.170 qualifies) | `/loop 5m <prompt>` inside a session |

---

## 1. Remote Control

### What it is

Remote Control bridges a local Claude Code CLI process to `claude.ai/code` and the Claude mobile app. All computation stays on the local machine; Anthropic's API relays messages over outbound HTTPS only (port 443, no inbound ports). The local session stays fully interactive while also accepting remote connections. This is the "phone approval / phone steering" use case from the harness roadmap.

### Evidence

**Local:** No binary output provided (LOCAL EVIDENCE field was undefined). Version v2.1.170 is confirmed in the task context. The minimum version requirement is v2.1.51 for core Remote Control, v2.1.110 for push notifications, and v2.1.162 for the status-line footer indicator. v2.1.170 satisfies all of these.

**Primary doc (fetched directly, `code.claude.com/docs/en/remote-control`):** Confirmed as platform-agnostic at the CLI level. No Windows-specific limitations section exists in the current doc. The outbound-HTTPS-only architecture is confirmed. Authentication requirement is a `claude.ai` OAuth session (NOT an API key). Plan requirement: Pro, Max, Team (admin must enable toggle), Enterprise (admin must enable toggle). The paid `claude.ai` plan in the task context satisfies the requirement without needing admin action.

**Blocking env vars (confirmed from primary doc):** `ANTHROPIC_API_KEY`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`. If any are set in the PowerShell environment or in `settings.json`'s `env` block, Remote Control will fail with the "not yet enabled for your account" error.

**Contradiction resolved:** Report 1 flagged a GitHub issue (issue 29006) suggesting the Desktop app had a bug with Remote Control at some earlier version. This is a past issue and not present in the current doc. The current official doc lists `/remote-control` as working from CLI and VS Code. The CLI path is confirmed; Desktop Code tab availability is not explicitly listed in the current remote-control doc. This is irrelevant here because the user is on the CLI (npm install), not the Desktop app.

### How to enable (exact steps, nothing runs automatically)

1. Confirm `claude.ai` authentication is active: run `claude auth status --text`. If not logged in with a claude.ai account, run `claude auth login` and choose the claude.ai option (not Console/API key option).
2. Confirm no blocking env vars: in PowerShell, run `$env:ANTHROPIC_API_KEY`, `$env:DISABLE_TELEMETRY`, `$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`. Each should return empty. If any are set, unset them for the session: `Remove-Item Env:ANTHROPIC_API_KEY`.
3. Navigate to the project directory: `cd C:\Users\qq\Desktop\mutwo-windows-claude-harness`.
4. **Option A - Interactive session with Remote Control:** run `claude --remote-control "harness-session"`. A "Remote Control active" indicator appears in the footer. A clickable session URL is shown.
5. **Option B - Server mode (no local interactive session, multiple remote connections):** run `claude remote-control --name "harness-server"`. Press spacebar to display a QR code.
6. **Option C - From existing session:** inside any running `claude` session, type `/remote-control` or `/rc`.
7. To make Remote Control auto-enable on every `claude` start: inside a session, run `/config` and set "Enable Remote Control for all sessions" to true.
8. To enable push notifications: install the Claude mobile app, sign in with the same account, grant notification permission on the phone, then inside Claude Code run `/config` and enable "Push when Claude decides".

### Cost and caps

- No additional cost. Remote Control is relayed via Anthropic's API but does not add token charges. The local session consumes subscription usage as normal.
- One remote session per interactive process (outside server mode). Server mode supports up to 32 concurrent sessions by default (`--capacity N` to change).
- Network outage exceeding approximately 10 minutes causes session timeout and process exit.
- Ultraplan sessions disconnect Remote Control (they share the same `claude.ai/code` interface slot).

### What it replaces in the harness roadmap

This is the "phone Allow/Deny approvals via ntfy" component from the roadmap. Instead of building a custom ntfy relay, Remote Control delivers mobile-accessible session control natively. It replaces the need for a custom notification push mechanism for human-in-the-loop permission approvals. The harness does not need to build a phone approval mod; Remote Control handles it. The only remaining harness concern is whether push notifications are reliable enough to act as approval prompts -- they are subject to iOS Focus mode and Android battery optimization suppression (UNVERIFIED: whether this is sufficient for the approval use case in practice).

---

## 2. Dispatch

### What it is

Dispatch is a persistent conversation in the Claude Desktop app's "Cowork" tab. You send tasks from the mobile app; Dispatch decides whether the task is development work (spawns a Claude Code session in the Desktop Code tab) or non-development work (handles it in Cowork). The spawned Code session has full local file access, MCP servers, and connectors. This is the "delegate work while away" use case.

### Evidence

**Primary doc (`code.claude.com/docs/en/desktop`, confirmed by Report 1):** Dispatch requires the Claude Desktop app (Windows x64 or ARM64 installer available; NOT the npm CLI package). It is NOT available in the CLI (`claude` terminal command). It requires Pro or Max plan. Team and Enterprise are explicitly NOT supported. The task context states the user is on a paid `claude.ai` plan; if that plan is Pro or Max, Dispatch is eligible.

**Local:** The harness is an npm install of Claude Code CLI (v2.1.170), NOT the Claude Desktop app. The Desktop app is a separate installation. Dispatch is therefore NOT currently available on this machine without a separate Desktop app install.

**Report 1 notes:** First-time Windows Code tab use in Desktop requires Git for Windows installed. The machine presumably has Git (the harness repo is a git repo), but this should be confirmed before Desktop install.

### How to enable (exact steps, nothing runs automatically)

Prerequisite: this requires installing the Claude Desktop app separately from the existing npm CLI.

1. Install Git for Windows if not already present: run `git --version` in PowerShell to check.
2. Download the Claude Desktop installer for Windows: visit `https://claude.ai/download` and download the Windows x64 installer (or ARM64 if applicable).
3. Install the Desktop app and sign in with the same `claude.ai` account used for CLI.
4. Install the Claude mobile app on the phone, sign in with the same account.
5. In the Desktop app, open the Cowork tab, click "Dispatch," and follow the pairing prompt (enable file access permissions when asked).
6. Pairing is account-based -- no separate device-pairing ceremony beyond being signed into the same `claude.ai` account on both apps.
7. To dispatch a task: open the Claude mobile app, navigate to Dispatch in the Cowork section, and send a task description.

### Cost and caps

- Dispatch uses subscription usage for each spawned Code session.
- Computer use: if enabled in Desktop, Dispatch-spawned Code sessions can use it, but approval permissions expire after 30 minutes in Dispatch sessions (vs full-session duration for regular sessions).
- Pro/Max only. No Team/Enterprise.

### What it replaces in the harness roadmap

This is the "web-dash prompt dispatch" concept from the roadmap -- sending tasks from the phone while away from the machine. Dispatch handles this natively if the Desktop app is installed. The "mission-control desktop UI" harness mod becomes less necessary if Dispatch is installed, since Dispatch already provides a desktop-integrated Code tab sidebar with session management. The key question is whether Dispatch's UX (mobile app -> Desktop Code tab) meets the user's needs, or whether the planned WPF mission-control mod adds value that Dispatch does not provide (hotkeys, canned prompts, custom state views reading `~/.claude/state/*.json`). These are complementary, not mutually exclusive: Dispatch handles remote dispatch; mission-control handles local session overview.

---

## 3. Background agents (`claude agents`)

### What it is

`claude agents` opens a fullscreen TUI (terminal UI) for managing multiple background sessions. Each background session runs under a supervisor process that survives terminal close and machine sleep (but not shutdown). Sessions can be started, monitored, peeked at, replied to, and stopped without leaving the TUI.

### Evidence

**Primary doc (`code.claude.com/docs/en/agent-view`, fetched directly):** Requires v2.1.139+. v2.1.170 qualifies. The supervisor process is a per-user background process that starts automatically on first `claude --bg` or `claude agents` call. File isolation: every background session gets its own git worktree under `.claude/worktrees/` before the first file edit (can be disabled with `worktree.bgIsolation: "none"` in settings, requires v2.1.143+). Row summaries are generated by a Haiku-class model, refreshed at most every 15 seconds, and billed as normal requests.

**Windows-specific (confirmed from primary doc):** `claude daemon status` surfaces pipe-key file errors explicitly on Windows. Recovery from an unresponsive supervisor: `claude daemon stop --any`, or if the supervisor does not respond to stop, find the PID from `claude daemon status` and run `taskkill /PID <pid>` in PowerShell.

**`--json` output fields confirmed from CLI reference (fetched directly):** `cwd`, `kind`, `startedAt` for all sessions; `id`, `state` (`working`, `blocked`, `done`, `failed`, `stopped`), `pid` (when alive), `status`, `waitingFor` (when status=waiting), `sessionId` (when set), `name` (when set) for background sessions.

**Not available in:** Claude Desktop Code tab (`/agents` listed as local-only terminal-dialog command in the Desktop docs).

### How to enable (exact steps, nothing runs automatically)

`claude agents` requires no installation or configuration change. It is available in the current CLI installation.

1. Open PowerShell and navigate to a project directory: `cd C:\Users\qq\Desktop\mutwo-windows-claude-harness`.
2. Run `claude agents` to open the agent view TUI.
3. Type a task in the dispatch input at the bottom and press Enter to start a background session.
4. Alternatively, from any running Claude session, press the left arrow key on an empty prompt to background the session and open agent view.
5. To start a background session directly without opening the TUI: `claude --bg "your task here"`.
6. To set defaults for all dispatched sessions: `claude agents --permission-mode plan --model sonnet`.
7. To check supervisor health: `claude daemon status`.
8. To list sessions as JSON for scripting: `claude agents --json` (active only) or `claude agents --json --all` (including completed).

**Note on worktree isolation:** The harness repo at `C:\Users\qq\Desktop\mutwo-windows-claude-harness` is a git repo. Background sessions started here will automatically create worktrees under `.claude/worktrees/`. This is desirable for parallel agent work; commit or merge worktree changes before deleting sessions.

### Cost and caps

- Row summary refreshes are billed as Haiku-class requests. Each refresh is one short request. At the 15-second maximum refresh rate with many active sessions, this can accumulate. For a budget-constrained user: consider using `claude agents --json` for scripted status polling instead of leaving the TUI open, or disable agent view summaries with `disableAgentView: true` in settings (this disables the full feature) or set `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`.
- No daily cap on background sessions beyond the subscription's general usage limits.
- Sessions survive sleep but not shutdown. On shutdown, sessions show as "failed." Recover with `claude respawn --all`.

### What it replaces in the harness roadmap

This directly enables the "CCManager for parallel sessions" roadmap item (listed as deferred). The built-in agent view TUI is more capable than a custom parallel-session manager would be. It also provides the `~/.claude/daemon/roster.json` and `~/.claude/jobs/<id>/state.json` files that the planned mission-control desktop UI can read. The harness's mission-control mod should read these files rather than implementing its own session tracking.

---

## 4. Voice mode

### What it is

Voice dictation lets the user speak prompts instead of typing them in the CLI. Audio is streamed to Anthropic's servers for transcription (not local). Two modes: hold (push-to-talk, hold Space) and tap (tap once to start, tap again to send). Available in the CLI session and in agent view's peek panel.

### Evidence

**Primary doc (`code.claude.com/docs/en/voice-dictation`, fetched directly):** Windows is a confirmed supported platform with a native audio module (not a fallback). Minimum version: v2.1.69 for base voice, v2.1.116 for tap mode. v2.1.170 qualifies for both. Authentication requirement: must be authenticated with a `claude.ai` account (NOT an API key, Bedrock, Vertex, Foundry, or when HIPAA is enabled). The task context confirms a paid `claude.ai` plan, which satisfies this.

**Windows microphone permission path (confirmed from primary doc):** Settings -> Privacy & security -> Microphone -> turn on for desktop apps. Audio device check: Settings -> System -> Sound -> Input.

**WSL note (confirmed from primary doc):** If running Claude Code in WSL rather than native Windows PowerShell, voice requires WSLg (WSL2 from Microsoft Store on Win 10/11). Since this harness uses the native Windows npm install, this note is not applicable.

**Voice does NOT consume Claude tokens or count toward `/usage` limits** (confirmed from primary doc). The doc does not state this is included free on Pro/Max in explicit pricing language. The researcher (Report 2) found search results claiming it is included at no extra cost; this is UNVERIFIED from the primary doc itself, but consistent with the "does not count toward limits" language. Treat as high-confidence but not primary-source-verified.

### How to enable (exact steps, nothing runs automatically)

1. Confirm microphone permission in Windows: Settings -> Privacy & security -> Microphone -> ensure "Let desktop apps access your microphone" is on.
2. Check the active input device: Settings -> System -> Sound -> Input -> confirm a microphone is listed and not muted.
3. Start a Claude session: `claude`.
4. Inside the session, type `/voice hold` (for push-to-talk) or `/voice tap` (for tap-to-record-and-send, recommended for most use).
5. Hold or tap Space to dictate. Release (hold mode) or tap again (tap mode) to finalize.
6. To persist the setting across sessions, add to `~/.claude/settings.json`:
   ```
   "voice": { "enabled": true, "mode": "tap" }
   ```
7. To rebind the dictation key away from Space (recommended to avoid accidental triggers), create `~/.claude/keybindings.json` with a modifier binding such as `meta+k` for `voice:pushToTalk` in the `Chat` context.

### Cost and caps

- No token cost; does not count toward `/usage` limits.
- Audio is processed on Anthropic's servers; each utterance is a transcription call, not billed as Claude tokens.
- Not available in remote environments or SSH sessions. Available only in the local CLI and VS Code extension (when VS Code is local).

### What it replaces in the harness roadmap

"DictaFlow" is listed as a deferred extra in the roadmap. Voice mode is the built-in equivalent. No custom voice input mod is needed. The harness roadmap item for DictaFlow can be closed.

---

## 5. Channels (Telegram/Discord)

### What it is

Channels are plugins that route messages from external chat apps (Telegram, Discord, iMessage) into a running local Claude Code session. Claude can receive messages and reply back through the same app. Events from CI, error tracking, or other webhook sources can also be pushed into the session. This is the "push CI results / error tracking alerts / deploy events into active session" pattern and the "chat bridge" for remote prompting.

### Evidence

**Primary doc (`code.claude.com/docs/en/channels`, confirmed by Report 2):** Research preview as of June 2026. Requires Claude Code v2.1.80+; v2.1.170 qualifies. Authentication: `claude.ai` account OR Console API key (broader than Remote Control). No Windows-specific restrictions in the channels doc. Requires Bun runtime -- this is a hard requirement; channels will not run on Node.js or Deno.

**Bun on Windows:** Bun officially supports Windows natively. The channels doc has no Windows carve-out. UNVERIFIED from the channels primary doc context specifically, but Bun Windows support is documented at bun.sh.

**iMessage:** macOS only (requires Full Disk Access to `~/Library/Messages/chat.db` and AppleScript). NOT available on Windows.

**Security architecture (confirmed from primary doc):** Sender allowlist per channel. Pairing flow bootstraps allowlist. Anyone who can reply through the channel can approve or deny Claude tool-use permission prompts -- this means only trusted sender IDs should be allowlisted. For unattended use, `--dangerously-skip-permissions` is available but should only be used in trusted environments.

**Bun is not currently installed** on this machine per available evidence (not confirmed in local evidence, which was undefined). Must be installed before channels work.

### How to enable (exact steps, nothing runs automatically)

**Telegram (recommended for the harness phone-dispatch use case):**

1. Install Bun: open PowerShell and run `powershell -c "irm bun.sh/install.ps1 | iex"`. Verify: `bun --version`.
2. Create a Telegram bot: in Telegram, message @BotFather, send `/newbot`, follow prompts, and copy the token.
3. Start a Claude session: `claude`.
4. Install the plugin: `/plugin install telegram@claude-plugins-official`, then `/reload-plugins`. If the marketplace is not found, first run `/plugin marketplace add anthropics/claude-plugins-official`.
5. Configure the token: `/telegram:configure <your-bot-token>` (saves to `~/.claude/channels/telegram/.env`).
6. Exit and relaunch with channels enabled: `claude --channels plugin:telegram@claude-plugins-official`.
7. In Telegram, DM the bot -- it replies with a pairing code.
8. In the Claude session: `/telegram:access pair <code>`.
9. Lock to your Telegram ID only: `/telegram:access policy allowlist`.
10. For always-on use: run the session in a persistent terminal (e.g., Windows Terminal with a profile that keeps the window open) or as a background session: `claude --bg --channels plugin:telegram@claude-plugins-official "monitor for messages"`.

**Discord:** Same pattern as Telegram but requires a Discord bot created in the Discord Developer Portal with Message Content Intent enabled before step 2.

### Cost and caps

- No additional plan cost beyond standard subscription usage. Channels themselves do not consume tokens; Claude's responses to messages do.
- Channels only deliver while the session is open. For always-on: keep the session running in a background process or persistent terminal.
- Team/Enterprise orgs: admin must enable `channelsEnabled`. The task context is a personal paid plan, so this does not apply.
- Plugin architecture is in research preview; flag syntax and the plugin API may change.

### What it replaces in the harness roadmap

Channels (specifically Telegram) replace the "web-dash prompt dispatch" concept and the "ntfy phone approval" concept for the use case of sending prompts to Claude from the phone. Combined with Remote Control (which steers a running session), the full mobile-to-Claude workflow is: Telegram channel for injecting new tasks / event-driven triggers, Remote Control for steering in-progress sessions from mobile. The harness does not need to build a custom notification or dispatch relay. The "daily-digest mod" trigger could use a `/loop` schedule or a cloud Routine instead of a channel.

---

## 6. Routines and scheduled agents

### 6a. Cloud Routines

#### What it is

A cloud Routine is a saved Claude Code configuration (prompt + GitHub repos + connectors) that runs on Anthropic-managed infrastructure on a schedule, on API call, or on GitHub events. The machine does not need to be on. This is the "daily-digest mod local scheduled task -> routines?" roadmap item.

#### Evidence

**Primary doc (`code.claude.com/docs/en/routines`, fetched directly):** Research preview as of April 14, 2026. Available on Pro, Max, Team, Enterprise (requires "Claude Code on the web" enabled). NOT available on Free plan. Requires v2.1.81+ for `/schedule` CLI command; v2.1.170 qualifies.

**`/schedule` blocked conditions (confirmed from primary doc):** `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` set in shell; `apiKeyHelper` in `settings.json`; `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, or `DISABLE_GROWTHBOOK` set; inside a Claude Code on the web session; CLI older than v2.1.81.

**Daily run cap (from primary doc):** The live routines doc states "routines have a daily cap on how many runs can start per account" and directs users to `claude.ai/code/routines` or `claude.ai/settings/usage` to view their current limits. The doc does NOT print per-plan numeric values. The Anthropic blog post (`claude.com/blog/introducing-routines-in-claude-code`) states Pro=5, Max=15, Team+Enterprise=25 runs/day. These numbers are UNVERIFIED from the primary doc (the live page was fetched directly and does not reproduce them). The blog figures are from a confirmed Anthropic source but may have been changed since publication given that routines are in research preview. Treat the Pro=5/Max=15/25 figures as directionally accurate but subject to change; confirm at `claude.ai/settings/usage`.

**Repo requirement:** GitHub only. Each repo is cloned fresh on every run from the default branch. The harness repo at `aadammbandaisha-create/threat-intel` would need to be added to the routine configuration. Commits/PRs appear under the account owner's GitHub identity.

**Limitation for daily-digest use case:** Cloud Routines have no access to local files. They clone repos fresh. They cannot read local transcript files at `~/.claude/` unless those files are committed to a GitHub repo. For a "daily transcript digest" use case that reads local session history, cloud Routines alone are insufficient -- either the transcript data must be pushed to GitHub first (via a local hook or Desktop scheduled task), or the digest must use a Desktop Scheduled Task instead.

#### How to enable (exact steps, nothing runs automatically)

1. Navigate to `claude.ai/code/routines` in a browser, signed in with the same account used for Claude Code.
2. Click "New routine."
3. Name it and write a prompt (must be self-contained and explicit; Routines run autonomously with no permission prompts).
4. Add the GitHub repo to clone (requires connected GitHub identity; if not connected, the CLI will prompt `/web-setup`).
5. Select an environment (Default/Trusted is sufficient for most cases).
6. Select a trigger: Schedule (preset: daily, weekdays, etc.), API (generates an HTTP endpoint + bearer token), or GitHub event (requires Claude GitHub App installed on the repo).
7. Click Create.
8. To create a scheduled routine from the CLI instead: inside a session, run `/schedule daily PR review at 9am` and follow the conversational prompts.
9. To use a custom cron interval (e.g., every 6 hours): create via CLI or web first, then run `/schedule update` in the CLI and set a cron expression. Minimum interval is 1 hour; sub-hourly cron expressions are rejected.

#### Cost and caps

- Runs draw subscription usage the same as interactive sessions.
- Daily run cap applies (Pro=5, Max=15, Team+Enterprise=25 per blog -- UNVERIFIED from live doc; confirm at `claude.ai/settings/usage`).
- One-off runs do NOT count against the daily cap. They draw regular subscription usage only.
- Overage billing: if usage credits enabled in Settings -> Billing, runs continue on metered overage when the cap or usage limit is hit.
- API trigger endpoint and beta header `anthropic-beta: experimental-cc-routine-2026-04-01` are explicitly subject to breaking changes during research preview.

### 6b. Desktop Scheduled Tasks

#### What it is

Local scheduled tasks in the Claude Desktop app. Runs on the local machine with direct access to local files. Minimum interval 1 minute (vs 1 hour for cloud Routines). No daily run cap mentioned in docs. Requires the Desktop app to be open and the machine to be awake.

#### Evidence

Requires the Claude Desktop app (separate install, not the npm CLI). See Section 2 (Dispatch) for Desktop app install instructions. Task config stored at `~/.claude/scheduled-tasks/<task-name>/SKILL.md`. No daily cap documented.

**For the daily-digest use case:** Desktop Scheduled Tasks are better suited than cloud Routines for a digest that reads local session transcripts, because they have direct local file access. A Desktop Scheduled Task running nightly can read `~/.claude/` transcript files and produce a digest.

#### How to enable (exact steps, nothing runs automatically)

Requires Claude Desktop app to be installed first (see Section 2).

1. Open the Desktop app.
2. Click "Routines" in the sidebar.
3. Click "New routine" and choose "Local" (not "Remote").
4. Set the schedule (Daily recommended for a digest; time picker defaults to 9am local time).
5. Write the task prompt.
6. Click Create.
7. Alternatively, ask Claude conversationally in any Desktop session: "Create a local scheduled task that runs every weeknight at 9pm and summarizes today's session transcripts."

### 6c. `/loop` (session-scoped scheduling)

#### What it is

`/loop` schedules a repeating prompt within an open CLI session. The session must remain open. This is simpler than Routines for lightweight in-session polling.

#### How to enable

Inside any running `claude` session: `/loop 5m check the deploy` (5-minute fixed interval), or `/loop check the deploy` (Claude chooses interval), or `/loop` alone (built-in maintenance prompt). No installation required. To disable: `CLAUDE_CODE_DISABLE_CRON=1` env var.

#### Cost and caps

- No daily cap. Each loop iteration consumes subscription usage.
- Tasks expire 7 days after creation (fires once more then self-deletes). Restored on `--resume`/`--continue` if not expired.

---

## Recommendations

Ordered by value-to-effort ratio for this specific machine, budget, and roadmap:

1. **Enable Remote Control immediately.** Zero setup beyond `claude auth login` (which is presumably already done). Run `claude --remote-control` to verify it works on this machine right now. This directly delivers the "phone Allow/Deny approvals" roadmap item with no harness code written. Set "Enable Remote Control for all sessions" in `/config` to make it persistent. Then enable push notifications via the Claude mobile app. This is the single highest-value action available today.

2. **Enable voice mode immediately.** Run `/voice tap` inside any session. Grant the microphone permission in Windows Privacy settings when prompted. Zero dependencies, zero cost (does not consume tokens). This closes the "DictaFlow" deferred roadmap item entirely. Optionally rebind the dictation key from Space to a modifier combo in `~/.claude/keybindings.json` to avoid accidental triggers while typing.

3. **Install Bun and set up a Telegram channel.** Bun is a one-line install. The Telegram bot setup takes 15-20 minutes. This delivers the phone-to-Claude task-dispatch capability (complementing Remote Control). Use Remote Control for steering in-progress sessions; use Telegram for injecting new task prompts or reacting to events (CI failures, deploy notifications). This replaces both the "web-dash prompt dispatch" and "ntfy relay" harness concepts without any custom code.

4. **Wire up a cloud Routine for the daily-digest use case.** Create a Routine at `claude.ai/code/routines` that runs on a nightly schedule against the harness repo. Note: cloud Routines cannot read local `~/.claude/` transcript files. For a digest of local session transcripts, use a Desktop Scheduled Task instead (requires the Desktop app). If the daily digest only needs to process what is committed to GitHub (e.g., handoff.md, session summaries committed by a hook), a cloud Routine works well. Decide which scope is needed before building.

5. **Validate `claude agents` TUI.** Run `claude agents` from the harness directory. No configuration needed. This is already available. Explore it before building any mission-control UI mod -- the built-in agent view may handle 80% of the mission-control use case. The mission-control WPF mod (from the roadmap) is still valuable for custom views (reading `~/.claude/daemon/roster.json`, hotkeys, canned prompts), but scope it to what agent view does NOT provide rather than duplicating it.

6. **Defer the Claude Desktop app install until the above are verified.** Dispatch and Desktop Scheduled Tasks both require the Desktop app. The Desktop app is a full separate install. Before investing in it, confirm that Remote Control + Telegram channels satisfy the mobile workflow needs. If they do, the Desktop app install becomes lower priority. If a local-file-reading nightly digest is needed (vs cloud Routines), install the Desktop app at that point.

**Items the built-ins make obsolete in the harness roadmap:**
- Custom ntfy phone approval relay -> replaced by Remote Control push notifications.
- DictaFlow voice input mod -> replaced by built-in voice mode.
- Web-dash prompt dispatch -> replaced by Telegram channel + Remote Control mobile steering.
- CCManager for parallel sessions -> replaced by `claude agents` TUI and `--bg` sessions.
- Custom session-state polling for mission-control -> the `~/.claude/daemon/roster.json` and `claude agents --json` output are the data sources; the mission-control mod should read these rather than implementing state tracking independently.

**UNVERIFIED claims in this document:**
- Per-plan daily Routine run caps (Pro=5, Max=15, Team+Enterprise=25): from Anthropic blog, not reproduced in the current live routines doc. Confirm at `claude.ai/settings/usage`.
- Voice mode included at no plan cost beyond subscription: implied by "does not count toward limits" in the primary doc; explicit per-plan pricing statement not found in the primary doc.
- Bun channel plugins running correctly on Windows in practice: Bun supports Windows officially but this was not tested or confirmed in the channels primary doc context.
- Whether Remote Control push notifications are reliable enough as human-in-the-loop permission approval prompts, given iOS Focus mode / Android battery optimization suppression.
- Whether a GitHub issue (29006) noting an earlier Remote Control bug in the Desktop app is fully resolved in the current version; this is irrelevant for the CLI-only path but noted for completeness.
