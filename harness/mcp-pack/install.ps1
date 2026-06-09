[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = "Stop"

$ServerName = "context7"

Write-Host ""
Write-Host "Install mcp-pack"
Write-Host "Adds MCP server: $ServerName  (user scope)"
Write-Host "Command:         npx -y @upstash/context7-mcp"
Write-Host ""
Write-Host "This mod does NOT touch settings.json."
Write-Host "The claude CLI manages ~/.claude.json itself."
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Apply these changes? [y/N]"
    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "Aborted."
        exit 1
    }
}

# --- idempotency check via list (avoids false-positive from error messages in 'mcp get') ---
Write-Host "Checking if $ServerName is already registered..."
$listCheck = claude mcp list
$alreadyExists = $false

foreach ($line in $listCheck) {
    $lineStr = [string]$line
    if ($lineStr -match [regex]::Escape($ServerName)) {
        $alreadyExists = $true
        break
    }
}

if ($alreadyExists) {
    Write-Host "$ServerName is already registered. Skipping add."
} else {
    Write-Host "Adding $ServerName at user scope..."
    # NOTE: must go through cmd /c. Invoking the claude.ps1 npm shim directly makes
    # PowerShell consume the "--" separator during parameter binding, so the claude
    # CLI then tries to parse "-y" as its own option and fails.
    try {
        $addOutput = cmd /c "claude mcp add --scope user $ServerName -- npx -y @upstash/context7-mcp"
        foreach ($line in $addOutput) {
            Write-Host "  $line"
        }
    } catch {
        Write-Host "  WARNING: add threw: $_"
    }

    # --- verify ---
    Write-Host "Verifying registration..."
    $listOutput = claude mcp list
    $verified = $false
    foreach ($line in $listOutput) {
        $lineStr = [string]$line
        if ($lineStr -match $ServerName) {
            $verified = $true
            break
        }
    }

    if ($verified) {
        Write-Host "Verified: $ServerName appears in claude mcp list."
    } else {
        Write-Host ""
        Write-Host "WARNING: $ServerName was not found in claude mcp list after add."
        Write-Host "The add may have failed. Run the command manually if needed (via cmd,"
        Write-Host "because PowerShell eats the -- separator when calling the claude shim):"
        Write-Host ""
        Write-Host "  cmd /c `"claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp`""
        Write-Host ""
        Write-Host "Continuing without failing the install."
    }
}

Write-Host ""
Write-Host "Installed mcp-pack."
Write-Host "Restart Claude Code to activate the context7 server."
Write-Host "On first use, Claude Code may prompt you to trust the server - approve it."
Write-Host ""
Write-Host "Optional: set a Context7 API key to raise rate limits:"
Write-Host "  cmd /c `"claude mcp add --scope user context7 -e CONTEXT7_API_KEY=<your-key> -- npx -y @upstash/context7-mcp`""
Write-Host "  (Get a key at: https://context7.com/dashboard)"
