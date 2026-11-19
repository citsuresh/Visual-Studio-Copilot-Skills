<#
.SYNOPSIS
One-shot native VS chat rename after a delayed, verified idle handoff.
.DESCRIPTION
Modifies one user-approved chat title through UI only. Never sends a chat message,
restarts VS, edits its store, or retries a failed rename. Writes text-free result facts.
.PARAMETER DelaySeconds
Initial delay (default 20). An independent worker can use 2 to remove unnecessary padding;
the final-message, stable-idle and draft checks still apply. Tracked jobs can prevent idle.
.PARAMETER ReadyMessageHash
SHA256 of the exact final handoff message, normalized to LF and trimmed. The visible
message and absence of Cancel must both be observed before any navigation.
.PARAMETER ResultPath
New private JSON result file outside Git. Existing result files are refused.
.PARAMETER ValidateOnly
Checks parameters, binary identity, host, current header and draft without input or writes.
Returns preflight and CLI timings; live results also include per-phase and CLI timings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UiExe,
    [Parameter(Mandatory)][string]$CursorScript,
    [Parameter(Mandatory)][int]$HostProcessId,
    [Parameter(Mandatory)][long]$HostStartTicks,
    [Parameter(Mandatory)][ValidatePattern('^0x[0-9A-Fa-f]+$')][string]$WindowHandle,
    [Parameter(Mandatory)][string]$ExpectedHeader,
    [Parameter(Mandatory)][string]$OldTitle,
    [Parameter(Mandatory)][ValidateLength(1,120)][string]$NewTitle,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ReadyMessageHash,
    [Parameter(Mandatory)][string]$ResultPath,
    [ValidateRange(1,300)][int]$DelaySeconds = 20,
    [ValidateRange(1,600)][int]$IdleTimeoutSeconds = 120,
    [ValidateRange(1,30)][int]$StableIdleSeconds = 3,
    [ValidateRange(100,5000)][int]$PollMilliseconds = 500,
    [ValidateRange(1,30)][int]$VerificationSeconds = 5,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$script:runTimer = [Diagnostics.Stopwatch]::StartNew()
$script:uiTimings = New-Object 'Collections.Generic.List[object]'
$script:phaseTimings = New-Object 'Collections.Generic.List[object]'
$script:lastTimedPhase = 'Preflight'
$script:phaseStartedMs = 0.0

function Get-MessageHash([string]$Text) {
    $normalized = ($Text -replace "`r`n?", "`n").Trim()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Test-IdleEvidence($Snapshot, [string]$Header) {
    return ($Snapshot.Header -ceq $Header -and $Snapshot.ReadyMessageSeen -eq $true -and
        $Snapshot.CancelCount -eq 0 -and $Snapshot.DraftEmpty -eq $true -and
        $Snapshot.RenameEditorCount -eq 0)
}

function Test-ClipboardPreserved($Reply) {
    if ($null -eq $Reply) { return $false }
    $snapshot = $Reply.PSObject.Properties['clipboardSnapshotComplete']
    if ($null -eq $snapshot -or $snapshot.Value -isnot [bool] -or -not $snapshot.Value) { return $false }
    $restored = $Reply.PSObject.Properties['clipboardRestored']
    if ($null -eq $restored) { return $true }
    return ($restored.Value -is [bool] -and $restored.Value)
}

function Confirm-HostForeground {
    $handle = [IntPtr][Convert]::ToInt64($WindowHandle.Substring(2), 16)
    Enable-AgentCursor
    try {
        if (-not (Set-AgentForegroundWindow -Handle $handle)) {
            throw 'Host foreground activation was not verified; no navigation or rename attempted.'
        }
    }
    finally { Restore-AgentCursor }
}

function Invoke-Ui([string[]]$Arguments, [switch]$InputAction) {
    $commandTimer = [Diagnostics.Stopwatch]::StartNew()
    $commandSucceeded = $false
    if ($InputAction) { Enable-AgentCursor }
    try {
        $raw = & $UiExe @Arguments
        $exitCode = $LASTEXITCODE
        $reply = ($raw -join "`n") | ConvertFrom-Json
        if ($exitCode -ne 0 -or $reply.success -ne $true) {
            throw "UI command $($Arguments[0]) failed: $($reply.error)"
        }
        $commandSucceeded = $true
        return $reply
    }
    finally {
        if ($InputAction) { Restore-AgentCursor }
        $script:uiTimings.Add([pscustomobject]@{
            verb = $Arguments[0]
            elapsedMs = [Math]::Round($commandTimer.Elapsed.TotalMilliseconds, 1)
            inputAction = [bool]$InputAction
            succeeded = $commandSucceeded
        })
    }
}

function Find-Visible($Scope, $Property, $Value) {
    $condition = New-Object Windows.Automation.PropertyCondition($Property, $Value)
    return @($Scope.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) |
        Where-Object { -not $_.Current.IsOffscreen })
}

function Find-Id($Scope, [string]$Id) {
    $matches = @(Find-Visible $Scope ([Windows.Automation.AutomationElement]::AutomationIdProperty) $Id)
    if ($matches.Count -ne 1) { throw "Expected one visible $Id control; found $($matches.Count)." }
    return $matches[0]
}

function Get-Chat {
    $process = Get-Process -Id $HostProcessId
    if ($process.ProcessName -ne 'devenv' -or $process.StartTime.ToUniversalTime().Ticks -ne $HostStartTicks) {
        throw 'Host process identity changed; no rediscovery or cross-instance fallback.'
    }
    $handle = [IntPtr][Convert]::ToInt64($WindowHandle.Substring(2), 16)
    $root = [Windows.Automation.AutomationElement]::FromHandle($handle)
    if ($root.Current.ProcessId -ne $HostProcessId) { throw 'Window ownership changed.' }
    $condition = New-Object Windows.Automation.AndCondition(
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'Chat')),
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty, 'GenericPane')))
    $panes = @($root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) |
        Where-Object { -not $_.Current.IsOffscreen })
    if ($panes.Count -ne 1) { throw "Expected one Chat pane; found $($panes.Count)." }
    return $panes[0]
}

function Get-RenameEditors($Chat) {
    $condition = New-Object Windows.Automation.AndCondition(
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, 'Rename')),
        (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit)))
    return @($Chat.FindAll([Windows.Automation.TreeScope]::Descendants, $condition) |
        Where-Object { -not $_.Current.IsOffscreen })
}

function Read-RenameTitle($Chat) {
    $editors = @(Get-RenameEditors $Chat)
    if ($editors.Count -ne 1) { throw 'Rename editor is missing or ambiguous.' }
    $valuePattern = $null
    if (-not $editors[0].TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
        throw 'Rename editor does not expose a readable ValuePattern.'
    }
    return $valuePattern.Current.Value
}

function Get-ChatSnapshot {
    $chat = Get-Chat
    $header = (Find-Id $chat 'title').Current.Name
    $list = Find-Id $chat 'session'
    $messages = $list.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
    $ready = $false
    for ($index = $messages.Count - 1; $index -ge 0; $index--) {
        if ((Get-MessageHash $messages[$index].Current.Name) -ieq $ReadyMessageHash) {
            $ready = $true
            break
        }
    }
    $input = Find-Id $chat 'WpfTextView'
    $textPattern = $null
    if (-not $input.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern, [ref]$textPattern)) {
        throw 'Cannot establish draft contents.'
    }
    return [pscustomobject]@{
        Header = $header
        ReadyMessageSeen = $ready
        CancelCount = @(Find-Visible $chat ([Windows.Automation.AutomationElement]::AutomationIdProperty) 'CancelButton').Count
        DraftEmpty = [string]::IsNullOrWhiteSpace($textPattern.DocumentRange.GetText(-1))
        RenameEditorCount = @(Get-RenameEditors $chat).Count
    }
}

function Write-Result {
    $elapsedMs = $script:runTimer.Elapsed.TotalMilliseconds
    if ($script:result.phase -cne $script:lastTimedPhase) {
        $script:phaseTimings.Add([pscustomobject]@{
            phase = $script:lastTimedPhase
            elapsedMs = [Math]::Round($elapsedMs - $script:phaseStartedMs, 1)
        })
        $script:lastTimedPhase = $script:result.phase
        $script:phaseStartedMs = $elapsedMs
    }
    $script:result.elapsedMs = [Math]::Round($elapsedMs, 1)
    $script:result.currentPhaseElapsedMs = [Math]::Round($elapsedMs - $script:phaseStartedMs, 1)
    $script:result.phaseTimings = @($script:phaseTimings.ToArray())
    $script:result.uiCommandTimings = @($script:uiTimings.ToArray())
    $script:result.updatedUtc = [DateTime]::UtcNow.ToString('o')
    $script:result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $UiExe -PathType Leaf)) { throw 'UI executable missing.' }
if (-not (Test-Path -LiteralPath $CursorScript -PathType Leaf)) { throw 'Cursor helper missing.' }
if (-not [IO.Path]::IsPathRooted($ResultPath) -or -not (Test-Path -LiteralPath (Split-Path $ResultPath -Parent) -PathType Container)) {
    throw 'ResultPath must be absolute with an existing private parent folder.'
}
if (Test-Path -LiteralPath $ResultPath) { throw 'ResultPath already exists; refusing to overwrite it.' }
if ($NewTitle -cne $NewTitle.Trim() -or $NewTitle -match '[\x00-\x1F\x7F]') { throw 'Title contains surrounding whitespace or control characters.' }
if (-not $ExpectedHeader.StartsWith($OldTitle + ', Working directory: ', [StringComparison]::Ordinal)) {
    throw 'ExpectedHeader does not match the explicitly approved old title and workspace.'
}
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$info = Invoke-Ui @('info')
if ($info.executablePath -ine [IO.Path]::GetFullPath($UiExe) -or
    $info.capabilities -notcontains 'ui.send-keys.window.v1') { throw 'Exact executable preflight failed.' }
$snapshot = Get-ChatSnapshot
if ($snapshot.Header -cne $ExpectedHeader -or -not $snapshot.DraftEmpty -or $snapshot.RenameEditorCount -ne 0) {
    throw "Initial preconditions failed: headerMatched=$($snapshot.Header -ceq $ExpectedHeader), draftEmpty=$($snapshot.DraftEmpty), renameEditors=$($snapshot.RenameEditorCount). No input sent."
}
if ($ValidateOnly) {
    [pscustomobject]@{
        validated = $true; hostMatched = $true; draftEmpty = $true; mutationAttempted = $false
        preflightElapsedMs = [Math]::Round($script:runTimer.Elapsed.TotalMilliseconds, 1)
        uiCommandTimings = @($script:uiTimings.ToArray())
    }
    return
}
. $CursorScript
$script:result = [ordered]@{
    state = 'Waiting'; phase = 'Delay'; workerProcessId = $PID
    idleVerified = $false; readyMessageSeen = $false; renameAttempted = $false
    foregroundVerified = $false
    typedTitleVerified = $false; enterSent = $false; savedTitleVerified = $false
    reopenedTitleVerified = $false; reopenedContextVerified = $false
    idleSampleCount = 0; lastIdleObservation = $null
    elapsedMs = 0.0; currentPhaseElapsedMs = 0.0; phaseTimings = @(); uiCommandTimings = @()
    cursorCleanupVerified = $false; updatedUtc = $null; failure = $null
}
$sessionOwned = $false
$failure = $null
Write-Result
try {
    Start-Sleep -Seconds $DelaySeconds
    $cursorStartReply = Invoke-Ui @('cursor-session', 'start', '--kind', 'UiAutomation')
    $sessionOwned = $cursorStartReply.changed -eq $true
    if (-not $sessionOwned) { throw 'Another cursor session owns the desktop; stopping this test.' }
    $script:result.phase = 'WaitingForIdle'
    Write-Result
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $idleSince = $null
    while ($true) {
        $snapshot = Get-ChatSnapshot
        $script:result.idleSampleCount++
        $script:result.readyMessageSeen = $script:result.readyMessageSeen -or $snapshot.ReadyMessageSeen
        $script:result.lastIdleObservation = [ordered]@{
            headerMatched = $snapshot.Header -ceq $ExpectedHeader
            readyMessageSeen = $snapshot.ReadyMessageSeen
            cancelCount = $snapshot.CancelCount
            draftEmpty = $snapshot.DraftEmpty
            renameEditorCount = $snapshot.RenameEditorCount
        }
        if ($snapshot.Header -cne $ExpectedHeader -or -not $snapshot.DraftEmpty -or $snapshot.RenameEditorCount -ne 0) {
            throw 'Chat changed, a draft appeared, or another rename is open; no input sent.'
        }
        if (Test-IdleEvidence $snapshot $ExpectedHeader) {
            if ($null -eq $idleSince) { $idleSince = $watch.Elapsed.TotalSeconds }
            if (($watch.Elapsed.TotalSeconds - $idleSince) -ge $StableIdleSeconds) { break }
        }
        else { $idleSince = $null }
        if ($watch.Elapsed.TotalSeconds -ge $IdleTimeoutSeconds) { throw 'Timed out awaiting the final handoff message and stable idle UI.' }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    $script:result.idleVerified = $true
    $script:result.readyMessageSeen = $true
    $script:result.phase = 'ActivateHost'
    Write-Result
    Confirm-HostForeground
    $script:result.foregroundVerified = $true
    $script:result.phase = 'NavigateToList'
    Write-Result
    $null = Invoke-Ui @('click', '--hwnd', $WindowHandle, '--strategy', 'AutomationId', '--value', 'backToHistory', '--controlType', 'Button') -InputAction
    $chat = Get-Chat
    if ((Find-Id $chat 'title').Current.Name -cne 'Sessions') { throw 'Session list header not verified.' }
    $prefix = 'Active session: ' + $OldTitle + ','
    $entries = @(Find-Visible $chat ([Windows.Automation.AutomationElement]::AutomationIdProperty) 'ItemOpenButton')
    $target = @($entries | Where-Object { $_.Current.Name.StartsWith($prefix, [StringComparison]::Ordinal) })
    if ($target.Count -ne 1) { throw 'Previously selected session row is missing or ambiguous.' }
    $null = Invoke-Ui @('right-click', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', $target[0].Current.Name) -InputAction
    $menu = Invoke-Ui @('find-all', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', 'Rename', '--controlType', 'MenuItem')
    if ($menu.count -ne 1) { throw 'Observed Rename menu is not unique.' }
    $null = Invoke-Ui @('click', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', 'Rename', '--controlType', 'MenuItem') -InputAction
    $script:result.renameAttempted = $true
    $script:result.phase = 'EditTitle'
    Write-Result
    $before = Read-RenameTitle $chat
    if ($before -cne $OldTitle) { throw 'Rename editor old title did not match; no title entered.' }
    $null = Invoke-Ui @('send-keys', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', 'Rename', '--focusMode', 'click', '--keys', '^a') -InputAction
    $paste = Invoke-Ui @('paste-text', '--hwnd', $WindowHandle, '--text', $NewTitle, '--restoreDelayMs', '1000') -InputAction
    if (-not (Test-ClipboardPreserved $paste)) { throw 'Clipboard preservation was not verified; title not committed.' }
    $typed = Read-RenameTitle $chat
    if ($typed -cne $NewTitle) { throw 'Explicit typed-title readback failed; title not committed.' }
    $script:result.typedTitleVerified = $true
    $null = Invoke-Ui @('send-keys', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', 'Rename', '--focusMode', 'none', '--keys', '{ENTER}') -InputAction
    $script:result.enterSent = $true
    $script:result.phase = 'VerifySavedTitle'
    Write-Result
    $verify = [Diagnostics.Stopwatch]::StartNew()
    $saved = @()
    while ($verify.Elapsed.TotalSeconds -lt $VerificationSeconds) {
        $chat = Get-Chat
        $editors = @(Get-RenameEditors $chat)
        $entries = @(Find-Visible $chat ([Windows.Automation.AutomationElement]::AutomationIdProperty) 'ItemOpenButton')
        $saved = @($entries | Where-Object { $_.Current.Name.StartsWith('Active session: ' + $NewTitle + ',', [StringComparison]::Ordinal) })
        if ($editors.Count -eq 0 -and $saved.Count -eq 1) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    if ($editors.Count -ne 0 -or $saved.Count -ne 1) { throw 'Enter did not produce a verified saved row and closed editor; no retry or restart.' }
    $script:result.savedTitleVerified = $true
    $script:result.phase = 'Reopen'
    Write-Result
    $null = Invoke-Ui @('click', '--hwnd', $WindowHandle, '--strategy', 'Name', '--value', $saved[0].Current.Name, '--controlType', 'Button') -InputAction
    $newHeader = $NewTitle + $ExpectedHeader.Substring($OldTitle.Length)
    $verify.Restart()
    do {
        $snapshot = Get-ChatSnapshot
        if ($snapshot.Header -ceq $newHeader -and $snapshot.ReadyMessageSeen) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($verify.Elapsed.TotalSeconds -lt $VerificationSeconds)
    if ($snapshot.Header -cne $newHeader -or -not $snapshot.ReadyMessageSeen) { throw 'Saved session could not be verified after reopening.' }
    $script:result.reopenedTitleVerified = $true
    $script:result.reopenedContextVerified = $true
    $script:result.state = 'Completed'
    $script:result.phase = 'Finished'
}
catch {
    $failure = $_
    $script:result.state = 'Failed'
    $script:result.failure = $_.Exception.Message
}
finally {
    if ($sessionOwned) {
        try {
            $null = Invoke-Ui @('cursor-session', 'stop', '--kind', 'UiAutomation')
            $script:result.cursorCleanupVerified = $true
        }
        catch {
            $script:result.state = 'Failed'
            $script:result.failure = 'Cursor session cleanup failed; manual cleanup is required.'
            if ($null -eq $failure) { $failure = $_ }
        }
    }
    Write-Result
}
$script:result | ConvertTo-Json -Depth 5
if ($null -ne $failure) { throw $failure }
