# mcp-pack

Curated MCP servers for a solo dev, installed via the claude CLI.

This mod does NOT edit any JSON files directly. The claude CLI manages
`~\.claude.json` itself; this mod only calls `claude mcp add/remove`.

## What it installs

### Context7 (installed automatically)

Context7 fetches version-specific library documentation on demand and injects
it into your Claude Code context. It kills hallucinated APIs: instead of
Claude inventing method signatures from training data, it pulls the actual
current docs for the library version you are using.

**Server name:** `context7`  
**Scope:** user (available across all projects)  
**Command:** `npx -y @upstash/context7-mcp`  
**Cost:** free basic tier; rate-limited without a key  

Usage: in a Claude Code session, ask Claude to "use context7" or refer to a
library and it will call the server automatically when docs are relevant.

### GitHub MCP (manual -- needs a PAT)

GitHub MCP gives Claude Code read/write access to your GitHub repos, issues,
and PRs. It requires a Personal Access Token, so it is not installed
automatically.

**Required token scopes:** `repo`, `read:org`

**Manual install command** (run via `cmd /c` -- PowerShell strips the `--`
separator when calling the `claude` npm shim, which breaks the command):

```powershell
cmd /c "claude mcp add --scope user github -e GITHUB_PERSONAL_ACCESS_TOKEN=<your-pat> -- npx -y @modelcontextprotocol/server-github"
```

Generate a PAT at: https://github.com/settings/tokens
Select "Fine-grained token" for per-repo scope, or "Classic" for org-wide.

## Install

```powershell
cd harness\mcp-pack
.\install.ps1        # interactive
.\install.ps1 -Yes   # unattended
```

Restart Claude Code after install. On first use, Claude Code may prompt you
to trust the context7 server - approve it.

## Uninstall

```powershell
.\uninstall.ps1
```

Removes the `context7` server from user scope. Does not affect GitHub MCP if
you added it manually.

## Ownership

This mod owns exactly one server registration:

- `context7` at user scope

Uninstall removes only that entry. No settings.json is touched.

## Cost and rate-limit notes

Context7 free tier is rate-limited. If you hit limits, get an API key at
https://context7.com/dashboard and re-add the server with the key:

```powershell
claude mcp remove --scope user context7
cmd /c "claude mcp add --scope user context7 -e CONTEXT7_API_KEY=<your-key> -- npx -y @upstash/context7-mcp"
```

Context7 docs calls do NOT consume Claude token budget -- they are
server-side fetches. The only cost is the key retrieval result in context.

## Security notes

- `npx -y` downloads and runs the MCP server package from npm on first use.
  Pin a specific version in production environments if supply-chain security
  matters: replace `@upstash/context7-mcp` with `@upstash/context7-mcp@x.y.z`.
- Your GITHUB_PERSONAL_ACCESS_TOKEN is stored in user-scope MCP config
  (`~\.claude.json`). Use a fine-grained token scoped to the repos you need.
