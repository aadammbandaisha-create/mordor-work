# windows-state-indicator

Windows adaptation of the upstream `tab-state-indicator` harness mod.

## What it does

Installs Claude Code hooks into:

```text
~\.claude\settings.json
```

The hooks run:

```text
UserPromptSubmit          -> working
PostToolUse               -> working
Stop                      -> idle
Notification              -> idle
PreToolUse AskUserQuestion -> idle
```

The runtime script writes state to:

```text
~\.claude\state\<session_id>.json
```

When Claude becomes idle, it also tries to send a Windows notification. If the
BurntToast PowerShell module is installed, it uses that. Otherwise it falls
back to a standard Windows Forms tray balloon where available.

It also ships an optional always-on-top status light:

```powershell
~\.claude\scripts\show-claude-state-light.ps1
```

The light turns green for `working`, red for `idle`, and gray before a Claude
Code hook has written state.

## Install

```powershell
cd C:\Users\qq\Desktop\mutwo-windows-claude-harness\harness\windows-state-indicator
.\install.ps1
```

For unattended install:

```powershell
.\install.ps1 -Yes
```

Restart Claude Code after installing.

## Uninstall

```powershell
.\uninstall.ps1
```

To remove state files too:

```powershell
.\uninstall.ps1 -RemoveState
```

## Optional title watcher

Claude Code hooks run as subprocesses, so they cannot reliably recolor an
existing Windows Terminal tab. If you want a visible terminal title indicator,
run this in a separate PowerShell tab:

```powershell
~\.claude\scripts\watch-claude-state.ps1
```

It watches the newest Claude state file and updates the current terminal title.

## Optional screen light

Run this if you want a visible green/red indicator on screen:

```powershell
~\.claude\scripts\show-claude-state-light.ps1
```

It opens a small always-on-top window in the top-right corner.

Note: the `mission-control` mod supersedes this light with a full dashboard
(session cards, context %, daily spend). The light keeps working if you
prefer the minimal version.

## Ownership

All hook commands include this sentinel:

```text
mordor:windows-state-indicator
```

The installer removes old entries with that sentinel before adding fresh ones.
The uninstaller removes only entries with that sentinel.
