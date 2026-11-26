<#
.SYNOPSIS
    Sends ONE single-line message into a Claude desktop chat (Claude.exe) through its chat box, using UI Automation only.

.DESCRIPTION
    For a Claude desktop chat the window is used once: for the first message, which tells the worker to run
    Wait-AgentMailbox.ps1. Every later message goes through the mailbox (Send-AgentMessage.ps1 -Channel). Copilot's
    Send-CopilotPrompt.ps1 does not work on this app. See agent-orchestrator/SKILL.md, "Target is a Claude desktop chat".

    No keyboard, mouse, window activation or focus change is used: the chat box (an Edit named "Prompt") is filled with
    ValuePattern.SetValue and the button named "Send" is invoked. Order, stopping at the first problem (no retries):
      1. Finds the Claude window (process claude, class Chrome_WidgetWin_1, title "Claude" unless -TitleContains), refuses
         the window of the calling chat (-AllowOwnHost to allow it on purpose) and a window on another virtual desktop.
      2. Waits for a quiet keyboard and mouse (Wait-AgentUserQuiet, no cue), unless -IgnoreUserActivity.
      3. Refuses while the chat is working (a button named "Stop" is present): the message would queue.
      4. Refuses when the box holds text (a draft is the person's); an empty box reads as one newline, so the value is trimmed.
         -OverwriteInput replaces it; use that only for your own leftover test text.
      5. SetValue, then polls the read-back every 50 ms for up to 1500 ms until it matches EXACTLY (the editor applies a set
         value asynchronously: an immediate read still shows the old value, and it matched at about 117 ms).
         A value that never matches is cleared again and nothing is sent.
      6. Invokes "Send" once and polls up to 3000 ms until the box is empty (about 334 ms observed).
    Only the ACTIVE chat in the window exposes a "Prompt". Multi-line text is refused (not verified). Never dump the window
    tree: it contains the whole visible chat.

.PARAMETER Hwnd
    Window handle (for example 0x2A04F6). Without it the window is found by process, class and title.

.PARAMETER TitleContains
    Window title substring instead of the exact title "Claude". More than one match is refused, never guessed.

.PARAMETER Text
    The single-line message.

.PARAMETER OverwriteInput
    Replace text already in the box. Never use it for a person's draft.

.PARAMETER AllowOwnHost
    Allow the window that hosts this script (the calling chat itself). For a deliberate test only.

.PARAMETER NoSend
    Dry run: fill and read back, then clear the box again without invoking Send.

.PARAMETER QuietSeconds
    Required idle time of the keyboard and mouse (default 3; 0 turns the wait off).

.PARAMETER MaxWaitSeconds
    How long to wait for a quiet keyboard before refusing (default 120).

.PARAMETER IgnoreUserActivity
    Skip the quiet wait. Only when the person says nobody is at the machine.

.PARAMETER WaitIdleSeconds
    How long to wait for a working chat (Stop button present) to become idle before refusing with ClaudeBusy
    (default 0: refuse at once). Typing is only ever done when the chat is idle.

.PARAMETER ReadBackTimeoutMs
    How long the read-back may take to match (default 1500).

.PARAMETER EmptyTimeoutMs
    How long the box may take to empty after Send (default 3000).

.PARAMETER AsJson
    Print the result as JSON.
#>
[CmdletBinding()]
param(
    [string]$Hwnd,
    [string]$TitleContains,
    [Parameter(Mandatory = $true)]
    [string]$Text,
    [switch]$OverwriteInput,
    [switch]$AllowOwnHost,
    [switch]$NoSend,
    [ValidateRange(0, 600)][int]$QuietSeconds = 3,
    [ValidateRange(0, 3600)][int]$MaxWaitSeconds = 120,
    [switch]$IgnoreUserActivity,
    [ValidateRange(0, 600)][int]$WaitIdleSeconds = 0,
    [ValidateRange(100, 30000)][int]$ReadBackTimeoutMs = 1500,
    [ValidateRange(100, 30000)][int]$EmptyTimeoutMs = 3000,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'

# ---- pure logic (tested offline in scripts\agent\Test-SendClaudePrompt.ps1) ----

# An empty Claude chat box reads as ONE newline, so a draft is anything left after trimming.
function Test-ClaudeDraft {
    param([string]$Value)
    return ([string]$Value).Trim().Length -gt 0
}

# Polls Reader (a script block returning the box value) until it equals Expected exactly (case-sensitive).
function Wait-ClaudeValue {
    param([scriptblock]$Reader, [string]$Expected, [int]$TimeoutMs = 1500, [int]$PollMs = 50)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $last = $null
    do {
        try { $last = [string](& $Reader) } catch { $last = $null }
        if ($null -ne $last -and $last -ceq $Expected) { return [pscustomobject]@{ Matched = $true; ElapsedMs = [int]$clock.ElapsedMilliseconds; Last = $last } }
        Start-Sleep -Milliseconds $PollMs
    } while ($clock.ElapsedMilliseconds -lt $TimeoutMs)
    return [pscustomobject]@{ Matched = $false; ElapsedMs = [int]$clock.ElapsedMilliseconds; Last = $last }
}

# Polls Reader until the trimmed box value is empty.
function Wait-ClaudeEmpty {
    param([scriptblock]$Reader, [int]$TimeoutMs = 3000, [int]$PollMs = 50)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $last = $null
    do {
        try { $last = [string](& $Reader) } catch { $last = $null }
        if ($null -ne $last -and -not (Test-ClaudeDraft $last)) { return [pscustomobject]@{ Matched = $true; ElapsedMs = [int]$clock.ElapsedMilliseconds; Last = $last } }
        Start-Sleep -Milliseconds $PollMs
    } while ($clock.ElapsedMilliseconds -lt $TimeoutMs)
    return [pscustomobject]@{ Matched = $false; ElapsedMs = [int]$clock.ElapsedMilliseconds; Last = $last }
}

# The send sequence with every UI action passed in as a script block, so it can be tested without a window.
# $Ui keys: IsBusy, ReadValue, SetValue (param $text), FindSend (returns the button or $null), InvokeSend (param $button).
function Invoke-ClaudeSend {
    param(
        [string]$Text, [hashtable]$Ui, [switch]$OverwriteInput, [switch]$NoSend,
        [int]$ReadBackTimeoutMs = 1500, [int]$EmptyTimeoutMs = 3000, [int]$PollMs = 50, [int]$WaitIdleMs = 0
    )
    $r = [ordered]@{ Sent = $false; Error = ''; ReadBackMs = $null; EmptyMs = $null; Cleared = $false }
    if ($Text -match "[`r`n]") { $r.Error = 'MultiLine: only a single-line message is supported (multi-line text was not verified). Nothing was typed.'; return [pscustomobject]$r }
    if ([string]::IsNullOrWhiteSpace($Text)) { $r.Error = 'EmptyText: nothing to send.'; return [pscustomobject]$r }
    $idleClock = [Diagnostics.Stopwatch]::StartNew()
    while (& $Ui.IsBusy) {
        if ($idleClock.ElapsedMilliseconds -ge $WaitIdleMs) {
            $r.Error = 'ClaudeBusy: the chat is working (the Stop button is present), so the message would queue. Nothing was typed; ' + $(if ($WaitIdleMs -gt 0) { "it was still working after $([int]($WaitIdleMs / 1000)) s." } else { 'wait until it is idle, or pass -WaitIdleSeconds.' })
            return [pscustomobject]$r
        }
        Start-Sleep -Milliseconds ([Math]::Max($PollMs, 5) * 10)
    }
    $before = $null
    try { $before = [string](& $Ui.ReadValue) } catch { $r.Error = "InputUnreadable: the chat box could not be read ($($_.Exception.Message)), so a draft cannot be ruled out. Nothing was typed."; return [pscustomobject]$r }
    if (Test-ClaudeDraft $before) {
        if (-not $OverwriteInput) { $r.Error = "DraftPresent: the chat box already holds $($before.Trim().Length) characters, which belong to the person or another agent. Nothing was typed; pass -OverwriteInput only for your own leftover text."; return [pscustomobject]$r }
    }
    & $Ui.SetValue $Text
    $rb = Wait-ClaudeValue -Reader $Ui.ReadValue -Expected $Text -TimeoutMs $ReadBackTimeoutMs -PollMs $PollMs
    $r.ReadBackMs = $rb.ElapsedMs
    if (-not $rb.Matched) {
        & $Ui.SetValue ''
        $clr = Wait-ClaudeEmpty -Reader $Ui.ReadValue -TimeoutMs $EmptyTimeoutMs -PollMs $PollMs
        $r.Cleared = [bool]$clr.Matched
        $r.Error = "ReadBackMismatch: the box did not hold the exact text within $ReadBackTimeoutMs ms. Nothing was sent. " + $(if ($clr.Matched) { 'The box was cleared again.' } else { 'The box could NOT be cleared: check it by hand.' })
        return [pscustomobject]$r
    }
    if ($NoSend) {
        & $Ui.SetValue ''
        $clr = Wait-ClaudeEmpty -Reader $Ui.ReadValue -TimeoutMs $EmptyTimeoutMs -PollMs $PollMs
        $r.Cleared = [bool]$clr.Matched
        if (-not $clr.Matched) { $r.Error = 'ClearFailed: the dry run could not clear the box; check it by hand.' }
        return [pscustomobject]$r
    }
    $button = & $Ui.FindSend
    if (-not $button) {
        & $Ui.SetValue ''
        $clr = Wait-ClaudeEmpty -Reader $Ui.ReadValue -TimeoutMs $EmptyTimeoutMs -PollMs $PollMs
        $r.Cleared = [bool]$clr.Matched
        $r.Error = 'SendButtonMissing: the Send button was not found or not enabled. Nothing was sent. ' + $(if ($clr.Matched) { 'The box was cleared again.' } else { 'The box could NOT be cleared: check it by hand.' })
        return [pscustomobject]$r
    }
    & $Ui.InvokeSend $button
    $e = Wait-ClaudeEmpty -Reader $Ui.ReadValue -TimeoutMs $EmptyTimeoutMs -PollMs $PollMs
    $r.EmptyMs = $e.ElapsedMs
    if ($e.Matched) { $r.Sent = $true } else { $r.Error = "SendUnconfirmed: Send was invoked but the box was not empty within $EmptyTimeoutMs ms. The message may not have been sent; look at the chat before sending again." }
    return [pscustomobject]$r
}

# ---- UI Automation (not run offline) ----

# The Claude windows: process claude, class Chrome_WidgetWin_1, exact title "Claude" (or containing -TitleContains).
function Find-ClaudeWindows {
    param([string]$TitleContains)
    $root = [Windows.Automation.AutomationElement]::RootElement
    $classCondition = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty, 'Chrome_WidgetWin_1')
    $found = New-Object System.Collections.ArrayList
    foreach ($w in $root.FindAll([Windows.Automation.TreeScope]::Children, $classCondition)) {
        $name = [string]$w.Current.Name
        if ($TitleContains) { if ($name -notlike "*$TitleContains*") { continue } }
        elseif ($name -ne 'Claude') { continue }
        $procName = ''
        try { $procName = (Get-Process -Id $w.Current.ProcessId -ErrorAction Stop).ProcessName } catch { }
        if ($procName -ne 'claude') { continue }
        [void]$found.Add([pscustomobject]@{ Hwnd = ('0x{0:X}' -f [int64]$w.Current.NativeWindowHandle); ProcessId = [int]$w.Current.ProcessId; Title = $name; Element = $w })
    }
    return @($found)
}

function Get-ClaudePromptElements {
    param($Window)
    $condition = New-Object Windows.Automation.AndCondition(
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'Prompt')),
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)))
    return @($Window.FindAll([Windows.Automation.TreeScope]::Descendants, $condition))
}

function Find-ClaudeButton {
    param($Window, [string]$ButtonName)
    $condition = New-Object Windows.Automation.AndCondition(
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, $ButtonName)),
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)))
    return $Window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
}

# This process and its ancestors (a parent that started after its child is a recycled PID, so the walk stops).
function Get-CallerProcessIds {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    $pairs = $null
    if ('AgentProcessNative' -as [type]) { $pairs = [AgentProcessNative]::ParentPairs() }
    if ($pairs) {
        $parentOf = @{}
        for ($i = 0; $i + 1 -lt $pairs.Length; $i += 2) { $parentOf[[int]$pairs[$i]] = [int]$pairs[$i + 1] }
        $current = [int]$PID
        if (-not $parentOf.ContainsKey($current)) { throw "Process $PID was not found." }
        $ids.Add($current)
        for ($depth = 0; $depth -lt 32; $depth++) {
            if (-not $parentOf.ContainsKey($current)) { break }
            $parent = $parentOf[$current]
            if (-not $parent -or -not $parentOf.ContainsKey($parent) -or $ids.Contains($parent)) { break }
            $childStart = [AgentProcessNative]::StartTime($current)
            $parentStart = [AgentProcessNative]::StartTime($parent)
            if ($childStart -gt 0 -and $parentStart -gt $childStart) { break }
            $ids.Add($parent)
            $current = $parent
        }
        return $ids.ToArray()
    }
    $byId = @{}
    foreach ($process in @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)) { $byId[[int]$process.ProcessId] = $process }
    $current = $byId[[int]$PID]
    if (-not $current) { throw "Process $PID was not found." }
    $ids.Add([int]$current.ProcessId)
    for ($depth = 0; $depth -lt 32 -and $current.ParentProcessId; $depth++) {
        $parent = $byId[[int]$current.ParentProcessId]
        if (-not $parent -or $parent.CreationDate -gt $current.CreationDate -or $ids.Contains([int]$parent.ProcessId)) { break }
        $ids.Add([int]$parent.ProcessId)
        $current = $parent
    }
    return $ids.ToArray()
}

function Write-Result {
    param($Result, [string]$Handle)
    $out = [ordered]@{ Sent = [bool]$Result.Sent; Error = [string]$Result.Error; Hwnd = $Handle; ReadBackMs = $Result.ReadBackMs; EmptyMs = $Result.EmptyMs; Cleared = [bool]$Result.Cleared; ElapsedMs = [int]$script:clock.ElapsedMilliseconds }
    if ($AsJson) { ([pscustomobject]$out) | ConvertTo-Json -Compress } else { [pscustomobject]$out }
}

# ---- main ----
$script:clock = [Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName UIAutomationClient
$fail = { param($message) Write-Result -Result ([pscustomobject]@{ Sent = $false; Error = $message; ReadBackMs = $null; EmptyMs = $null; Cleared = $false }) -Handle $Hwnd }

# Loaded for its native process helper (own-host and desktop checks) and the quiet wait (user courtesy).
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor

$window = $null
if ($Hwnd) {
    try { $window = [Windows.Automation.AutomationElement]::FromHandle([IntPtr][Convert]::ToInt64($Hwnd, 16)) } catch { $window = $null }
    $isClaude = $false
    if ($window) {
        try { $isClaude = ($window.Current.ClassName -eq 'Chrome_WidgetWin_1') -and ((Get-Process -Id $window.Current.ProcessId -ErrorAction Stop).ProcessName -eq 'claude') } catch { }
    }
    if (-not $isClaude) { return (& $fail "NotClaudeWindow: $Hwnd is not a Claude desktop window (process claude, class Chrome_WidgetWin_1), or it no longer exists. Nothing was typed.") }
    $windowPid = [int]$window.Current.ProcessId
}
else {
    $candidates = @(Find-ClaudeWindows -TitleContains $TitleContains)
    if ($candidates.Count -eq 0) { return (& $fail 'ClaudeWindowNotFound: no Claude desktop window was found (it may be on another virtual desktop). Nothing was typed.') }
    if ($candidates.Count -gt 1) { return (& $fail ("AmbiguousWindow: " + $candidates.Count + " Claude windows match (" + (($candidates | ForEach-Object { $_.Hwnd }) -join ', ') + "). Pass -Hwnd or -TitleContains. Nothing was typed.")) }
    $window = $candidates[0].Element; $Hwnd = $candidates[0].Hwnd; $windowPid = $candidates[0].ProcessId
}

if (-not $AllowOwnHost) {
    try { $callerIds = @(Get-CallerProcessIds) }
    catch { return (& $fail "OwnHostCheckFailed: could not read this script's process chain ($($_.Exception.Message)). Nothing was typed; use -AllowOwnHost to skip the check.") }
    if ($callerIds -contains $windowPid) { return (& $fail "OwnHostWindow: window $Hwnd belongs to process $windowPid, which hosts this script, so it would type into the calling chat itself. Nothing was typed; pass -AllowOwnHost if that is intended.") }
}
try {
    if ('AgentProcessNative' -as [type]) {
        if ([AgentProcessNative]::IsOnOtherDesktop([IntPtr][Convert]::ToInt64($Hwnd, 16))) { return (& $fail "Window $Hwnd is on another virtual desktop. Nothing was typed; ask the person to switch to that desktop, then try again.") }
    }
}
catch { }

$prompts = @(Get-ClaudePromptElements -Window $window)
if ($prompts.Count -ne 1) { return (& $fail "PromptNotFound: found $($prompts.Count) chat boxes named Prompt (exactly one is expected: only the active chat exposes one). Nothing was typed.") }

if (-not $IgnoreUserActivity -and $QuietSeconds -gt 0) {
    $quiet = Wait-AgentUserQuiet -QuietMilliseconds ($QuietSeconds * 1000) -DraftQuietMilliseconds ($QuietSeconds * 1000) -MaxWaitMilliseconds ($MaxWaitSeconds * 1000) -NoCue
    if (-not $quiet.Quiet) { return (& $fail "UserActive: the keyboard or mouse was in use for $MaxWaitSeconds s ($($quiet.Reason)). Nothing was typed; try again when the person is away.") }
}

$script:ClaudeWindow = $window
$ui = @{
    IsBusy      = { [bool](Find-ClaudeButton -Window $script:ClaudeWindow -ButtonName 'Stop') }
    ReadValue   = {
        $edit = @(Get-ClaudePromptElements -Window $script:ClaudeWindow)
        if ($edit.Count -ne 1) { throw 'Prompt not found' }
        [string]($edit[0].GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)).Current.Value
    }
    SetValue    = {
        param($value)
        $edit = @(Get-ClaudePromptElements -Window $script:ClaudeWindow)
        if ($edit.Count -ne 1) { throw 'Prompt not found' }
        ($edit[0].GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)).SetValue([string]$value)
    }
    FindSend    = {
        $b = Find-ClaudeButton -Window $script:ClaudeWindow -ButtonName 'Send'
        if ($b -and $b.Current.IsEnabled) { $b } else { $null }
    }
    InvokeSend  = { param($button) ($button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)).Invoke() }
}
$result = Invoke-ClaudeSend -Text $Text -Ui $ui -OverwriteInput:$OverwriteInput -NoSend:$NoSend -ReadBackTimeoutMs $ReadBackTimeoutMs -EmptyTimeoutMs $EmptyTimeoutMs -WaitIdleMs ($WaitIdleSeconds * 1000)
Write-Result -Result $result -Handle $Hwnd
