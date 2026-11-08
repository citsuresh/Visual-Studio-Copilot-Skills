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
    Target window handle, e.g. "0x60AAA". Optional when -TitleContains is given. A handle goes
    stale when Visual Studio is restarted; use -TitleContains to look it up each time.

.PARAMETER TitleContains
    Resolve the target window by title substring (list-windows --all --titleContains) instead
    of passing a handle. Fails with Sent=false when no window matches, and lists the candidates
    when more than one matches. Ignored when -Hwnd is also given. Declared last so the
    positional order of the other parameters is unchanged.

.PARAMETER Text
    Prompt text. Must be a single line; the CLI rejects embedded newlines.

.PARAMETER NewSession
    Click "Create new session" (AutomationId createNewThread) before pasting. A new session can
    take longer than 10 seconds to show its input; the script waits up to 30.

.PARAMETER Retries
    Extra clear-and-paste attempts after a verification mismatch. Default 2.

.PARAMETER NoSend
    Paste and verify only; do not click Send. Useful for testing.

.PARAMETER IgnoreBanners
    Send even if the chat shows a HarnessWorkspaceMismatchBanner ("The open folder is outside
    this session's working directory") or WorkspaceTrustWarningBanner. By default the script
    refuses and returns Sent=false, because the agent would run in the wrong folder.

.PARAMETER InputName
    UIA Name of the chat input. Default "Ask Copilot".

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.PARAMETER NoNavigate
    Do not look for the chat. By default, when the chat input is not showing, the script first
    selects the "Chat" tab (it can sit behind a sibling tab such as Git Changes in the same pane)
    and, if the pane then shows only the session list, creates a new session. Pass this to
    require the chat to be open already.

.PARAMETER Quiet
    On success, return InputText as $null instead of echoing the whole prompt back. Failures
    still return the text that was read from the input, since it explains the failure.

.OUTPUTS
    PSCustomObject (or JSON with -AsJson): Sent, Attempts, InputText, Error. When the window
    cannot be brought to the foreground and it no longer exists, Error says so (typically
    Visual Studio was restarted and the handle is stale). When the window exists but still
    cannot be brought forward after one retry, Error tells the person to click the target
    window and run the script again; the script does not loop.

.EXAMPLE
    .\Send-CopilotPrompt.ps1 -Hwnd 0x60AAA -NewSession -Text 'Run Bootstrap.'

.EXAMPLE
    .\Send-CopilotPrompt.ps1 -TitleContains 'AgentDebugToolkit - ' -Quiet -AsJson -Text 'Continue.'
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    [switch]$NewSession,

    [ValidateRange(0, 10)]
    [int]$Retries = 2,

    [switch]$NoSend,

    [switch]$IgnoreBanners,

    [string]$InputName = 'Ask Copilot',

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe',

    [switch]$AsJson,

    [switch]$Quiet,

    [string]$TitleContains,

    [switch]$NoNavigate
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
if (-not $Hwnd -and -not $TitleContains) {
    throw "Pass -Hwnd or -TitleContains."
}

function Invoke-Ui {
    param([string[]]$Arguments)
    $raw = (& $ExePath @Arguments 2>&1 | Out-String).Trim()
    try { return $raw | ConvertFrom-Json } catch { return [pscustomobject]@{ success = $false; error = 'unparseable-output'; message = $raw } }
}

function Write-Result {
    param([bool]$Sent, [int]$Attempts, [string]$InputText, [string]$ErrorText)
    if ($Quiet -and $Sent) { $InputText = $null }
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

function Get-TopLevelWindows {
    param([string[]]$Filter = @())
    $r = Invoke-Ui (@('list-windows', '--all') + $Filter)
    # The leading comma keeps an empty list an empty array; a bare empty array would unroll to $null,
    # which this function uses to mean "the listing failed".
    if ($r.success) { return ,@($r.windows) }
    $script:ListWindowsError = "$($r.error) $($r.message)".Trim()
    return $null
}

# Explains a foreground failure: a handle that is no longer in the window list means the
# window was closed or Visual Studio was restarted, which is the usual cause of a stale handle.
function Get-ForegroundFailureText {
    $wanted = [Convert]::ToInt64($Hwnd, 16)
    $windows = Get-TopLevelWindows
    if ($null -eq $windows) {
        return "Could not bring the target window to the foreground, and the window list failed too ($script:ListWindowsError)."
    }
    $present = @($windows | Where-Object { [Convert]::ToInt64($_.Hwnd, 16) -eq $wanted })
    if ($present.Count -eq 0) {
        return "Window $Hwnd no longer exists (the app may have been restarted, so the handle is stale). Look it up again, or pass -TitleContains."
    }
    return 'Could not bring the target window to the foreground, even after a second try (Windows can refuse to let a background process take focus). Click the target Visual Studio window yourself, then run this again.'
}

# Brings the target forward; on failure waits a moment and tries once more (not a loop).
function Request-Foreground {
    $h = [IntPtr][Convert]::ToInt64($Hwnd, 16)
    if (Set-AgentForegroundWindow -Handle $h) { return $true }
    Start-Sleep -Seconds 1
    return [bool](Set-AgentForegroundWindow -Handle $h)
}

function Test-ChatInput {
    param([int]$TimeoutMs = 1500)
    $r = Invoke-Ui @('wait-for-element', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--state', 'enabled', '--timeoutMs', [string]$TimeoutMs)
    return [bool]$r.success
}

# The Chat tab can sit behind a sibling tab in the same pane (for example Git Changes), in which
# case neither the input nor the "Create new session" button is rendered. Select the Chat tab.
function Select-ChatTabIfHidden {
    if (Test-ChatInput) { return }
    $button = Invoke-Ui @('wait-for-element', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread', '--timeoutMs', '1000')
    if ($button.success) { return }
    $null = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', 'Chat', '--controlType', 'TabItem')
}

# With the Chat tab showing but no input, the pane is on its session list: create a session.
# Returns $null when the input is ready, otherwise an error text.
function Ensure-ChatInput {
    if (Test-ChatInput) { return $null }
    $created = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread')
    if (-not $created.success) {
        return "The chat input is not showing and a new session could not be created: $($created.error) $($created.message)"
    }
    if (Test-ChatInput -TimeoutMs 30000) { return $null }
    return 'The chat input did not appear after creating a session.'
}

if (-not $Hwnd) {
    $found = Get-TopLevelWindows -Filter @('--titleContains', $TitleContains)
    if ($null -eq $found) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Could not list windows to resolve -TitleContains '$TitleContains': $script:ListWindowsError. Nothing was typed."
    }
    $candidates = @($found)
    if ($candidates.Count -eq 0) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "No window title contains '$TitleContains'. Nothing was typed."
    }
    if ($candidates.Count -gt 1) {
        $list = ($candidates | ForEach-Object { "$($_.Hwnd) '$($_.Title)'" }) -join '; '
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "More than one window title contains '$TitleContains': $list. Pass -Hwnd or a longer -TitleContains. Nothing was typed."
    }
    $Hwnd = [string]$candidates[0].Hwnd
}


# Red-dot cursor while this script activates the window, types and clicks; always restored.
# Shared with ui-interaction; agent-orchestrator and ui-interaction are sibling skill folders.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor
Enable-AgentCursor
try {
    # Bring the target forward first; input verbs refuse to type into a background window.
    if (-not (Request-Foreground)) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "$(Get-ForegroundFailureText) Nothing was typed or clicked."
    }
    if (-not $NoNavigate) { Select-ChatTabIfHidden }

    # Banner check before any input; banners only render while the chat is visible.
    if (-not $IgnoreBanners) {
        $tree = (& $ExePath inspect --hwnd $Hwnd --maxDepth 25 2>&1 | Out-String)
        $found = @([regex]::Matches($tree, '"automationId"\s*:\s*"(HarnessWorkspaceMismatchBanner|WorkspaceTrustWarningBanner)"', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        if ($found.Count -gt 0) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Chat shows $($found -join ', '): the session's folder does not match the open folder (or is untrusted). Nothing was typed. Ask the user, then fix it or pass -IgnoreBanners."
        }
    }

    if ($NewSession) {
        $created = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread')
        if (-not $created.success) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Could not create a new session: $($created.error) $($created.message)"
        }
        # A new session can take well over 10 seconds to render its input.
        if (-not (Test-ChatInput -TimeoutMs 30000)) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'Chat input did not appear after creating a session.'
        }
    }
    elseif (-not $NoNavigate) {
        $chatError = Ensure-ChatInput
        if ($chatError) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "$chatError Nothing was typed."
        }
    }
    elseif (-not (Test-ChatInput -TimeoutMs 5000)) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'The chat input is not showing (-NoNavigate was given). Nothing was typed.'
    }

    $attempt = 0
    $lastError = $null
    $actual = $null
    while ($attempt -le $Retries) {
        $attempt++
        if (-not (Set-AgentForegroundWindow -Handle ([IntPtr][Convert]::ToInt64($Hwnd, 16)))) {
            $lastError = Get-ForegroundFailureText
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
