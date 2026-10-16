<#
.SYNOPSIS
    Sends a prompt to a VS Copilot Chat window, and only clicks Send after the pasted text is
    verified to match exactly.

.DESCRIPTION
    Optionally starts a new chat session, clears the chat input, pastes the prompt, and reads
    it back. If the input contains anything other than the exact prompt (for example stray
    keystrokes typed into the window during the paste), it clears and retries. If it still
    does not match after -Retries attempts, it does NOT send and returns Sent=false.

.PARAMETER Hwnd
    Target window handle, e.g. "0x60AAA".

.PARAMETER Text
    Prompt text. Must be a single line; the CLI rejects embedded newlines.

.PARAMETER NewSession
    Click "Create new session" (AutomationId createNewThread) before pasting.

.PARAMETER Retries
    Extra clear-and-paste attempts after a verification mismatch. Default 2.

.PARAMETER NoSend
    Paste and verify only; do not click Send. Useful for testing.

.PARAMETER InputName
    UIA Name of the chat input. Default "Ask Copilot".

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.OUTPUTS
    PSCustomObject (or JSON with -AsJson): Sent, Attempts, InputText, Error.

.EXAMPLE
    .\Send-CopilotPrompt.ps1 -Hwnd 0x60AAA -NewSession -Text 'Run Bootstrap.'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Hwnd,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    [switch]$NewSession,

    [ValidateRange(0, 10)]
    [int]$Retries = 2,

    [switch]$NoSend,

    [string]$InputName = 'Ask Copilot',

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe',

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue

if (-not (Test-Path $ExePath)) {
    throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly."
}
if ($Text -match "[`r`n]") {
    throw "-Text must be a single line; the chat CLI rejects embedded newlines."
}

function Invoke-Ui {
    param([string[]]$Arguments)
    $raw = (& $ExePath @Arguments 2>&1 | Out-String).Trim()
    try { return $raw | ConvertFrom-Json } catch { return [pscustomobject]@{ success = $false; error = 'unparseable-output'; message = $raw } }
}

function Write-Result {
    param([bool]$Sent, [int]$Attempts, [string]$InputText, [string]$ErrorText)
    $result = [pscustomobject]@{ Sent = $Sent; Attempts = $Attempts; InputText = $InputText; Error = $ErrorText }
    if ($AsJson) { $result | ConvertTo-Json -Depth 3 } else { $result }
}

function Clear-ChatInput {
    $cleared = Invoke-Ui @('type', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--clear')
    if (-not $cleared.success) {
        # Fall back to keyboard selection when the input exposes no writable ValuePattern.
        $null = Invoke-Ui @('send-keys', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--keys', '^a{DEL}')
    }
}

# Red-dot cursor while this script activates the window, types and clicks; always restored.
# Shared with ui-interaction; agent-orchestrator and ui-interaction are sibling skill folders.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor
Enable-AgentCursor
try {
    if ($NewSession) {
        # Bring the target forward first; input verbs refuse to type into a background window.
        if (-not (Set-AgentForegroundWindow -Handle ([IntPtr][Convert]::ToInt64($Hwnd, 16)))) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'Could not bring the target window to the foreground; nothing was typed or clicked.'
        }
        $created = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread')
        if (-not $created.success) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Could not create a new session: $($created.error) $($created.message)"
        }
        $ready = Invoke-Ui @('wait-for-element', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--state', 'enabled', '--timeoutMs', '10000')
        if (-not $ready.success) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Chat input did not appear after creating a session: $($ready.error)"
        }
    }

    $attempt = 0
    $lastError = $null
    $actual = $null
    while ($attempt -le $Retries) {
        $attempt++
        if (-not (Set-AgentForegroundWindow -Handle ([IntPtr][Convert]::ToInt64($Hwnd, 16)))) {
            $lastError = 'Could not bring the target window to the foreground.'
            continue
        }
        Clear-ChatInput
        $typed = Invoke-Ui @('type', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--text', $Text, '--paste', '--verify')
        if ($typed.success) {
            $actual = $Text
            $lastError = $null
            break
        }
        $actual = $typed.actual
        $lastError = "$($typed.error): $($typed.message)"
        Write-Host "[attempt $attempt] paste did not verify ($($typed.error)); actual='$actual'" -ForegroundColor Yellow
    }

    if ($lastError) {
        Clear-ChatInput
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText "Not sent; input never matched the prompt. Last error: $lastError"
    }

    if ($NoSend) {
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText $null
    }

    $sent = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'SendButton')
    if (-not $sent.success) {
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText "Send click failed: $($sent.error) $($sent.message)"
    }
    Write-Result -Sent $true -Attempts $attempt -InputText $actual -ErrorText $null
}
finally {
    Restore-AgentCursor
}
