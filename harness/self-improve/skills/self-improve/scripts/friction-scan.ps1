[CmdletBinding()]
param(
    [int]$Days = 7
)

$ErrorActionPreference = "SilentlyContinue"

function Out-Json {
    param([object]$Value)
    try {
        Write-Output ($Value | ConvertTo-Json -Depth 10 -Compress)
    } catch {
        Write-Output '{"error":"ConvertTo-Json failed"}'
    }
    exit 0
}

try {
    $ClaudeDir = Join-Path $env:USERPROFILE ".claude"
    $ProjectsDir = Join-Path $ClaudeDir "projects"

    if (-not (Test-Path -LiteralPath $ProjectsDir)) {
        Out-Json @{
            daysScanned = $Days
            sessionsScanned = 0
            signals = @{
                permissionDenials = @{ count = 0; examples = @() }
                toolErrors = @{ count = 0; topPatterns = @() }
                apiRetries = 0
                longSessions = 0
                bashCommandTop = @()
            }
        }
    }

    $cutoff = (Get-Date).AddDays(-$Days)

    # Collect all .jsonl files modified within the window
    $files = Get-ChildItem -LiteralPath $ProjectsDir -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff }

    $sessionsScanned = 0
    $permissionCount = 0
    $permissionExamples = [System.Collections.Generic.List[string]]::new()
    $toolErrorCount = 0
    # pattern -> count hashtable
    $toolErrorPatterns = @{}
    $apiRetries = 0
    $longSessions = 0
    # command-token -> count hashtable
    $bashCommands = @{}

    foreach ($file in $files) {
        $sessionsScanned++

        $fileSize = $file.Length
        if ($fileSize -gt 4MB) {
            $longSessions++
        }

        try {
            $reader = [System.IO.File]::OpenText($file.FullName)
            while (-not $reader.EndOfStream) {
                $line = $null
                try {
                    $line = $reader.ReadLine()
                } catch {
                    continue
                }
                if ($null -eq $line -or $line.Length -eq 0) {
                    continue
                }

                # Permission denials -- fast string check before JSON parse
                if ($line -match 'Permission for this action was denied' -or $line -match "doesn't want to proceed") {
                    $permissionCount++
                    if ($permissionExamples.Count -lt 5) {
                        # Try to extract the content text from tool_result; fall back to raw snippet
                        $snippet = ""
                        try {
                            $pobj = $line | ConvertFrom-Json -ErrorAction Stop
                            $items = @()
                            if ($pobj.PSObject.Properties.Name -contains "message") {
                                $pmsg = $pobj.message
                                if ($pmsg.PSObject.Properties.Name -contains "content") {
                                    $items = @($pmsg.content)
                                }
                            }
                            foreach ($item in $items) {
                                if ($item.PSObject.Properties.Name -contains "content") {
                                    $raw = $item.content
                                    if ($raw -is [string] -and $raw.Length -gt 0) {
                                        $snippet = $raw.Substring(0, [Math]::Min($raw.Length, 80))
                                        break
                                    }
                                }
                            }
                        } catch {}
                        if ($snippet.Length -eq 0) {
                            $snippet = $line.Substring(0, [Math]::Min($line.Length, 80))
                        }
                        $permissionExamples.Add($snippet)
                    }
                }

                # API retries
                if ($line -match 'API Error' -or $line -match 'overloaded_error') {
                    $apiRetries++
                }

                # Tool errors and bash commands require JSON parse
                if ($line -match '"is_error":true' -or $line -match '"type":"tool_use"') {
                    $obj = $null
                    try {
                        $obj = $line | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        continue
                    }

                    # Tool errors: lines with is_error:true in message.content array
                    if ($line -match '"is_error":true') {
                        # Content items may be array or the whole message
                        $contentItems = @()
                        if ($obj.PSObject.Properties.Name -contains "message") {
                            $msg = $obj.message
                            if ($msg.PSObject.Properties.Name -contains "content") {
                                $contentItems = @($msg.content)
                            }
                        }
                        foreach ($item in $contentItems) {
                            if ($item.PSObject.Properties.Name -contains "is_error" -and $item.is_error -eq $true) {
                                $toolErrorCount++
                                $errText = ""
                                if ($item.PSObject.Properties.Name -contains "content") {
                                    $rawContent = $item.content
                                    if ($rawContent -is [string]) {
                                        $errText = $rawContent
                                    } elseif ($rawContent -is [System.Array]) {
                                        foreach ($c in $rawContent) {
                                            if ($c.PSObject.Properties.Name -contains "text") {
                                                $errText = [string]$c.text
                                                break
                                            }
                                        }
                                    }
                                }
                                $patternKey = $errText.Substring(0, [Math]::Min($errText.Length, 60)).Trim()
                                if ($patternKey.Length -eq 0) { $patternKey = "(empty)" }
                                if ($toolErrorPatterns.ContainsKey($patternKey)) {
                                    $toolErrorPatterns[$patternKey]++
                                } else {
                                    $toolErrorPatterns[$patternKey] = 1
                                }
                            }
                        }
                    }

                    # Bash/PowerShell commands in assistant tool_use entries
                    if ($line -match '"type":"tool_use"' -and $null -ne $obj) {
                        $msgContent = @()
                        if ($obj.PSObject.Properties.Name -contains "message") {
                            $msgObj = $obj.message
                            if ($msgObj.PSObject.Properties.Name -contains "content") {
                                $msgContent = @($msgObj.content)
                            }
                        }
                        foreach ($item in $msgContent) {
                            if ($item.PSObject.Properties.Name -contains "type" -and
                                $item.PSObject.Properties.Name -contains "name" -and
                                $item.type -eq "tool_use" -and
                                ($item.name -eq "Bash" -or $item.name -eq "PowerShell")) {
                                $cmdText = ""
                                if ($item.PSObject.Properties.Name -contains "input") {
                                    $inp = $item.input
                                    if ($inp.PSObject.Properties.Name -contains "command") {
                                        $cmdText = [string]$inp.command
                                    }
                                }
                                if ($cmdText.Length -gt 0) {
                                    # Extract first token and optional second token (subcommand)
                                    $tokens = $cmdText.Trim() -split '\s+', 3
                                    $firstToken = $tokens[0]
                                    # Strip leading punctuation chars like & or ;
                                    $firstToken = $firstToken.TrimStart('&', ';', '(', '"', "'")
                                    $key = $firstToken
                                    if ($tokens.Count -ge 2) {
                                        $second = $tokens[1]
                                        # Include subcommand only if it looks like a plain word (git log, npm install, etc.)
                                        if ($second -match '^[a-zA-Z][a-zA-Z0-9_-]*$') {
                                            $key = "$firstToken $second"
                                        }
                                    }
                                    if ($key.Length -gt 0) {
                                        if ($bashCommands.ContainsKey($key)) {
                                            $bashCommands[$key]++
                                        } else {
                                            $bashCommands[$key] = 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            $reader.Close()
        } catch {
            # Tolerate unreadable files
        }
    }

    # Build top 5 tool error patterns
    $topErrors = $toolErrorPatterns.GetEnumerator() |
        Sort-Object { $_.Value } -Descending |
        Select-Object -First 5 |
        ForEach-Object { [pscustomobject]@{ pattern = $_.Key; count = $_.Value } }

    # Build top 10 bash commands
    $topBash = $bashCommands.GetEnumerator() |
        Sort-Object { $_.Value } -Descending |
        Select-Object -First 10 |
        ForEach-Object { [pscustomobject]@{ command = $_.Key; count = $_.Value } }

    $result = [pscustomobject]@{
        daysScanned = $Days
        sessionsScanned = $sessionsScanned
        signals = [pscustomobject]@{
            permissionDenials = [pscustomobject]@{
                count = $permissionCount
                examples = $permissionExamples.ToArray()
            }
            toolErrors = [pscustomobject]@{
                count = $toolErrorCount
                topPatterns = @($topErrors)
            }
            apiRetries = $apiRetries
            longSessions = $longSessions
            bashCommandTop = @($topBash)
        }
    }

    Out-Json $result

} catch {
    Write-Output ("{""error"":""" + ($_.Exception.Message -replace '"', "'") + """}")
    exit 0
}
