[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ServerName = "context7"

Write-Host "Removing MCP server: $ServerName (user scope)..."

try {
    $removeOutput = claude mcp remove --scope user $ServerName 2>&1
    foreach ($line in $removeOutput) {
        Write-Host "  $line"
    }
} catch {
    Write-Host "  $ServerName was not present (already clean)."
}

Write-Host "Uninstalled mcp-pack. ($ServerName removed from user scope, or was not present)"
