<#
.SYNOPSIS
Offline checks of the user-activity helpers in ui-interaction\scripts\AgentCursor.ps1: the quiet wait, the
draft-aware buffer, the input stamp and the focus handback. No window, keyboard, mouse, clipboard or focus is
touched; the native calls are replaced by mocks after the file is dot-sourced.
.PARAMETER CursorScriptPath
AgentCursor.ps1 to load. Default: the one in the sibling ui-interaction skill.
#>
[CmdletBinding()]
param([string]$CursorScriptPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if (-not $CursorScriptPath) { $CursorScriptPath = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1' }
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
. $CursorScriptPath

# Keep the real versions of the functions that get mocked below, so their own logic can still be tested.
$realDoNotDisturb = ${function:Get-AgentDoNotDisturbReason}
$realNoUserInputSinceOwn = ${function:Test-AgentNoUserInputSinceOwn}

# --- mocks: nothing below reaches the real keyboard, mouse or windows ---
$script:dnd = $null           # what Get-AgentDoNotDisturbReason reports
function Get-AgentDoNotDisturbReason { return $script:dnd }
$script:ownOnly = $false      # whether only agent input has happened since the last agent block
function Test-AgentNoUserInputSinceOwn { return $script:ownOnly }
$script:requests = 0; $script:lastSpeak = $null
function Request-AgentUserPause { param([switch]$Speak, [string]$Text) $script:requests++; $script:lastSpeak = [bool]$Speak }
function Invoke-AgentCueSound { }
$script:idle = 10000          # milliseconds since the last input
$script:draft = $false
$script:stamp = 100
$script:foreground = [IntPtr]10
$script:pointer = [pscustomobject]@{ X = 500; Y = 400 }
$script:windows = @(10, 20)
$script:focusedIs = $true
$script:calls = New-Object 'Collections.Generic.List[string]'
$script:cueShown = 0; $script:cueHidden = 0   # the amber waiting dot must never touch the real cursor in a test
function Show-AgentWaitingCue { $script:cueShown++ }
function Hide-AgentWaitingCue { $script:cueHidden++ }
$script:inUse = $null         # $null, 'MouseButton' or 'Modifier'
$script:buttonPressed = $false   # whether a mouse button was pressed since the last look
function Test-AgentMouseButtonPressed { return $script:buttonPressed }
function Get-AgentInputInUse { return $script:inUse }
function Get-AgentUserIdleMilliseconds { return $script:idle }
function Test-AgentForegroundDraft { return $script:draft }
function Get-AgentInputStamp { return [uint32]$script:stamp }
function Get-AgentForegroundHandle { return $script:foreground }
function Test-AgentWindowExists { param([IntPtr]$Handle) return ($script:windows -contains [int]$Handle) }
function Get-AgentPointerPosition { return $script:pointer }
function Set-AgentPointerPosition { param([int]$X, [int]$Y) $script:calls.Add("pointer:$X,$Y"); $script:pointer = [pscustomobject]@{ X = $X; Y = $Y } }
function Set-AgentForegroundWindow { param([IntPtr]$Handle, [int]$Attempts = 3) $script:calls.Add("foreground:$([int]$Handle)"); $script:foreground = $Handle; return $true }
function Test-AgentFocusedElementIs { param($Element) return $script:focusedIs }

# --- Wait-AgentUserQuiet ---
$script:idle = 10000
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 1000
Assert-True ($r.Quiet -and $r.Reason -eq 'Idle' -and $r.WaitedMilliseconds -lt 200) 'An already idle user must not be waited for.'
$script:idle = 100
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20
Assert-True (-not $r.Quiet -and $r.Reason -eq 'UserActive' -and $r.WaitedMilliseconds -ge 300) 'A user who stays active must make the wait give up.'
$script:idle = 2950
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 2000 -PollMilliseconds 20
# idle is a fixed mock; it never reaches the threshold, so this must time out, not proceed
Assert-True (-not $r.Quiet) 'Idle just under the threshold must not count as quiet.'
$script:idle = -1
$r = Wait-AgentUserQuiet -MaxWaitMilliseconds 100
Assert-True ($r.Quiet -and $r.Reason -eq 'IdleUnknown') 'An unreadable idle time must let the caller proceed and say so.'
# draft-aware buffer: 4 s idle is enough normally, not while a draft is open
$script:idle = 4000; $script:draft = $false
Assert-True ((Wait-AgentUserQuiet -QuietMilliseconds 3000 -DraftQuietMilliseconds 6000 -MaxWaitMilliseconds 200).Quiet) '4 s idle must be quiet without a draft.'
$script:draft = $true
Assert-True (-not (Wait-AgentUserQuiet -QuietMilliseconds 3000 -DraftQuietMilliseconds 6000 -MaxWaitMilliseconds 200 -PollMilliseconds 20).Quiet) '4 s idle must not be quiet while a draft is open.'
$script:idle = 7000
Assert-True ((Wait-AgentUserQuiet -QuietMilliseconds 3000 -DraftQuietMilliseconds 6000 -MaxWaitMilliseconds 200).Quiet) '7 s idle must be quiet even with a draft.'
# the user resumes typing during the wait: the wait restarts and eventually succeeds once they stop
$script:draft = $false
$script:idle = 500
$timer = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentUserIdleMilliseconds { return [int](500 + $timer.ElapsedMilliseconds * 20) }   # idle grows 20x faster than real time
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 2000 -PollMilliseconds 20
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -gt 50) 'The wait must end once idle time reaches the threshold, after waiting.'
function Get-AgentUserIdleMilliseconds { return $script:idle }

# held mouse button or modifier: not quiet however long the idle time is, because holding produces no new event
$script:idle = 60000; $script:inUse = 'MouseButton'
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20
Assert-True (-not $r.Quiet -and $r.Reason -eq 'UserActive' -and $r.InUse -eq 'MouseButton') 'A held mouse button must block the wait even after a long idle time.'
$script:inUse = 'Modifier'
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20
Assert-True (-not $r.Quiet -and $r.InUse -eq 'Modifier') 'A held modifier key must block the wait.'
$script:idle = -1; $script:inUse = 'MouseButton'
Assert-True (-not (Wait-AgentUserQuiet -MaxWaitMilliseconds 200 -PollMilliseconds 20).Quiet) 'A held button must block even when the idle time cannot be read.'
$script:inUse = $null; $script:idle = 10000
# the button is released while we wait: proceeds, and never earlier than the release
$script:inUse = 'MouseButton'
$releaseTimer = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentInputInUse { if ($releaseTimer.ElapsedMilliseconds -lt 250) { return 'MouseButton' } else { return $null } }
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 2000 -PollMilliseconds 20
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -ge 200) 'A released button must let the wait finish, but not before the release.'
function Get-AgentInputInUse { return $script:inUse }
$script:inUse = $null

# --- the amber waiting dot ---
$script:idle = 10000; $script:inUse = $null; $script:cueShown = 0; $script:cueHidden = 0
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 1000
Assert-True (-not $r.CueShown -and $script:cueShown -eq 0 -and $script:cueHidden -eq 0) 'No cue may be shown when the person is already idle.'
$script:idle = 100; $script:cueShown = 0; $script:cueHidden = 0
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 400 -PollMilliseconds 20 -CueAfterMilliseconds 100
Assert-True (-not $r.Quiet -and $r.CueShown -and $script:cueShown -eq 1 -and $script:cueHidden -eq 1) 'A long wait must show the cue once and clear it once, also when it times out.'
$script:cueShown = 0; $script:cueHidden = 0
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 400 -PollMilliseconds 20 -CueAfterMilliseconds 100 -NoCue
Assert-True ($script:cueShown -eq 0 -and $script:cueHidden -eq 0 -and -not $r.CueShown) '-NoCue must never show the cue.'
$script:cueShown = 0; $script:cueHidden = 0
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 400 -PollMilliseconds 20 -CueAfterMilliseconds 5000
Assert-True ($script:cueShown -eq 0) 'A wait shorter than the cue delay must not flash the cue.'
# the cue shows while waiting and is cleared when the person finally pauses
$script:cueShown = 0; $script:cueHidden = 0
$cueTimer = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentUserIdleMilliseconds { if ($cueTimer.ElapsedMilliseconds -lt 300) { return 50 } else { return 10000 } }
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 2000 -PollMilliseconds 20 -CueAfterMilliseconds 100
Assert-True ($r.Quiet -and $r.CueShown -and $script:cueShown -eq 1 -and $script:cueHidden -eq 1) 'The cue must be cleared when the person pauses and the wait succeeds.'
# an error while waiting must still clear the cue
$script:cueShown = 0; $script:cueHidden = 0
$errTimer = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentUserIdleMilliseconds { if ($errTimer.ElapsedMilliseconds -lt 200) { return 50 } else { throw 'boom' } }
$threw = $false
try { [void](Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 5000 -PollMilliseconds 20 -CueAfterMilliseconds 50) } catch { $threw = $true }
Assert-True ($threw -and $script:cueShown -eq 1 -and $script:cueHidden -eq 1) 'The cue must be cleared even when the wait fails.'
function Get-AgentUserIdleMilliseconds { return $script:idle }
$script:idle = 10000

# --- do not disturb, own-input shortcut and the spoken request in the wait ---
$script:idle = 60000; $script:inUse = $null; $script:ownOnly = $false
$script:dnd = 'FullScreenOrPresenting'
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20
Assert-True (-not $r.Quiet -and $r.Reason -eq 'DoNotDisturb' -and $r.InUse -eq 'FullScreenOrPresenting') 'A do-not-disturb state must block the wait however long the person has been idle.'
Assert-True ((Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20 -IgnoreDoNotDisturb).Quiet) '-IgnoreDoNotDisturb must skip the state check.'
$script:dnd = 'SessionNotPresent'
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 5000 -PollMilliseconds 20
Assert-True (-not $r.Quiet -and $r.Reason -eq 'SessionNotPresent' -and $r.WaitedMilliseconds -lt 500) 'A locked or absent session must return at once, not wait.'
$script:dnd = 'ManualPause'; $script:idle = 60000
$timer2 = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentDoNotDisturbReason { if ($timer2.ElapsedMilliseconds -lt 250) { return 'ManualPause' } else { return $null } }
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 3000 -PollMilliseconds 20
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -ge 200) 'A cleared pause must let the wait finish, but not before it is cleared.'
function Get-AgentDoNotDisturbReason { return $script:dnd }
$script:dnd = $null
# agent-only input since the last agent block: no idle wait, but a held button still blocks
$script:idle = 50; $script:ownOnly = $true
$r = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 1000
Assert-True ($r.Quiet -and $r.Reason -eq 'OwnInputOnly' -and $r.WaitedMilliseconds -lt 200 -and -not $r.CueShown) 'Input that was only the agents'' own must not be waited for.'
$script:inUse = 'MouseButton'
Assert-True (-not (Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 200 -PollMilliseconds 20).Quiet) 'The own-input shortcut must not override a held mouse button.'
$script:inUse = $null; $script:dnd = 'PresentationMode'
Assert-True (-not (Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 200 -PollMilliseconds 20).Quiet) 'The own-input shortcut must not override presenting.'
$script:dnd = $null; $script:ownOnly = $false
# the longer wait asks the person to pause, once
$script:idle = 100; $script:requests = 0; $script:lastSpeak = $null
$null = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 500 -PollMilliseconds 20 -RequestAfterMilliseconds 100
Assert-True ($script:requests -eq 1 -and $script:lastSpeak -eq $false) 'A long wait must ask once, without speech by default.'
$script:requests = 0
$null = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 500 -PollMilliseconds 20 -RequestAfterMilliseconds 100 -SpeakRequest
Assert-True ($script:requests -eq 1 -and $script:lastSpeak -eq $true) '-SpeakRequest must pass speech on to the request.'
$script:requests = 0
$null = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 500 -PollMilliseconds 20 -RequestAfterMilliseconds 100 -NoCue
Assert-True ($script:requests -eq 0) '-NoCue must also silence the request.'
$script:requests = 0
$null = Wait-AgentUserQuiet -QuietMilliseconds 3000 -MaxWaitMilliseconds 300 -PollMilliseconds 20 -RequestAfterMilliseconds 5000
Assert-True ($script:requests -eq 0) 'A wait shorter than the request delay must not ask.'

# --- the real do-not-disturb logic, with only the Windows readings mocked ---
$script:pausePath = Join-Path ([IO.Path]::GetTempPath()) ('agent-pause-' + [guid]::NewGuid().ToString('N') + '.flag')
function Get-AgentPausePath { return $script:pausePath }
$script:notifState = 5; $script:guiFlags = 0
function Get-AgentNotificationState { return $script:notifState }
function Get-AgentForegroundGuiFlags { return $script:guiFlags }
try {
    Assert-True ($null -eq (& $realDoNotDisturb)) 'A normal desktop must not be do-not-disturb.'
    foreach ($case in @(@(1, 'SessionNotPresent'), @(2, 'FullScreenOrPresenting'), @(3, 'FullScreenGame'), @(4, 'PresentationMode'), @(6, 'QuietTime'), @(7, 'FullScreenApp'))) {
        $script:notifState = $case[0]
        Assert-True ((& $realDoNotDisturb) -eq $case[1]) "Windows state $($case[0]) must read as $($case[1])."
    }
    $script:notifState = 5
    foreach ($flag in 0x2, 0x4, 0x10, 0x6) { $script:guiFlags = $flag; Assert-True ((& $realDoNotDisturb) -eq 'MenuOrDragInProgress') "GUI flag $flag must read as a menu or drag in progress." }
    foreach ($flag in 0x1, 0x8) { $script:guiFlags = $flag; Assert-True ($null -eq (& $realDoNotDisturb)) "GUI flag $flag (caret blink, system menu) must not block." }
    $script:guiFlags = 0
    Set-AgentUiPause -Minutes 5
    Assert-True ((& $realDoNotDisturb) -eq 'ManualPause') 'A manual pause with time left must block.'
    [IO.File]::WriteAllText($script:pausePath, "until=$((Get-Date).AddMinutes(-1).ToUniversalTime().ToString('o'))")
    Assert-True ($null -eq (& $realDoNotDisturb)) 'An expired manual pause must not block.'
    [IO.File]::WriteAllText($script:pausePath, 'pause')
    Assert-True ((& $realDoNotDisturb) -eq 'ManualPause') 'A pause marker without an end time must block until it is cleared.'
    Clear-AgentUiPause
    Assert-True (-not (Test-Path -LiteralPath $script:pausePath) -and $null -eq (& $realDoNotDisturb)) 'Clearing the pause must remove it.'
}
finally { Remove-Item -LiteralPath $script:pausePath -ErrorAction SilentlyContinue }

# --- the real shared own-input stamp, in a temp file ---
$script:stampPath = Join-Path ([IO.Path]::GetTempPath()) ('agent-stamp-' + [guid]::NewGuid().ToString('N') + '.stamp')
function Get-AgentOwnStampPath { return $script:stampPath }
try {
    $script:stamp = 777
    Assert-True (-not (& $realNoUserInputSinceOwn)) 'Without a recorded stamp nothing may count as own input.'
    Set-AgentOwnInputStamp
    Assert-True (& $realNoUserInputSinceOwn) 'The same stamp must read as no user input since the agent''s own.'
    $script:stamp = 778
    Assert-True (-not (& $realNoUserInputSinceOwn)) 'A changed stamp must read as user input.'
    $script:stamp = 0; Set-AgentOwnInputStamp
    Assert-True (-not (& $realNoUserInputSinceOwn)) 'An unreadable (0) stamp must never count as own input.'
}
finally { Remove-Item -LiteralPath $script:stampPath -ErrorAction SilentlyContinue }
$script:stamp = 100

# --- the lock: a second holder waits and then gives up; after release it can enter ---
$lockName = 'Local\AgentUiTest-' + [guid]::NewGuid().ToString('N')
$lock = Enter-AgentUiLock -TimeoutMilliseconds 1000 -Name $lockName
Assert-True ($null -ne $lock) 'The first holder must get the lock.'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$probe = "`$ErrorActionPreference='Stop'; . '$CursorScriptPath'; `$l = Enter-AgentUiLock -TimeoutMilliseconds 400 -Name '$lockName'; if (`$l) { 'got'; Exit-AgentUiLock `$l } else { 'timeout' }"
$out = (& $psExe -NoLogo -NoProfile -Command $probe 2>&1 | Out-String).Trim()
Assert-True ($out -eq 'timeout') "A second process must not get the lock while it is held (got: $out)."
Exit-AgentUiLock $lock
$out = (& $psExe -NoLogo -NoProfile -Command $probe 2>&1 | Out-String).Trim()
Assert-True ($out -eq 'got') "After release another process must get the lock (got: $out)."

# --- pointer movement alone is not the person using the mouse; typing, clicks and scrolling are ---
$script:buttonPressed = $false
$script:stamp = 100; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }
$mark = [pscustomobject]@{ X = 500; Y = 400 }
Assert-True (-not (Test-AgentMeaningfulInputSince -Stamp 100 -Point $mark)) 'An unchanged stamp is no input.'
$script:stamp = 101
Assert-True (Test-AgentMeaningfulInputSince -Stamp 100 -Point $mark) 'An input event with the pointer still (typing, a click on the spot, scrolling) must count.'
Assert-True (Test-AgentMeaningfulInputSince -Stamp 100) 'Without a pointer mark any change must count.'
foreach ($case in @(@(501, 400), @(500, 399), @(508, 408), @(540, 400), @(900, 700))) {
    $script:pointer = [pscustomobject]@{ X = $case[0]; Y = $case[1] }
    Assert-True (-not (Test-AgentMeaningfulInputSince -Stamp 100 -Point $mark)) "Moving the pointer to ($($case[0]),$($case[1])) alone, whatever the distance, must not count."
}
$script:buttonPressed = $true
Assert-True (Test-AgentMeaningfulInputSince -Stamp 100 -Point $mark) 'A button press must count even when the pointer moved to where it clicked.'
$script:buttonPressed = $false; $script:stamp = 100; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }

# the quiet wait with a moving pointer: input events every 40 ms, each with the pointer somewhere else
$script:dnd = $null; $script:inUse = $null; $script:ownOnly = $false; $script:idle = 10000
$jt = [Diagnostics.Stopwatch]::StartNew()
function Get-AgentInputStamp { return [uint32](1000 + [int]($jt.ElapsedMilliseconds / 40)) }
function Get-AgentUserIdleMilliseconds { return [int]($jt.ElapsedMilliseconds % 40) }
function Get-AgentPointerPosition { $s = 1000 + [int]($jt.ElapsedMilliseconds / 40); return [pscustomobject]@{ X = (500 + ($s % 2) * 3); Y = 400 } }
$r = Wait-AgentUserQuiet -QuietMilliseconds 300 -MaxWaitMilliseconds 3000 -PollMilliseconds 20 -NoCue
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -ge 250) 'A moving pointer alone must not stop the wait from finishing, and it must still wait the quiet period.'
function Get-AgentPointerPosition { $s = 1000 + [int]($jt.ElapsedMilliseconds / 40); return [pscustomobject]@{ X = (500 + ($s % 2) * 400); Y = 400 } }
$jt.Restart()
$r = Wait-AgentUserQuiet -QuietMilliseconds 300 -MaxWaitMilliseconds 3000 -PollMilliseconds 20 -NoCue
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -ge 250) 'A big sweep of the pointer must not count as using the mouse either.'
# the same events with the pointer still are typing, a click on the spot or scrolling: never quiet
function Get-AgentPointerPosition { return [pscustomobject]@{ X = 500; Y = 400 } }
$jt.Restart()
$r = Wait-AgentUserQuiet -QuietMilliseconds 300 -MaxWaitMilliseconds 600 -PollMilliseconds 20 -NoCue
Assert-True (-not $r.Quiet -and $r.Reason -eq 'UserActive') 'Input events with the pointer still must keep the wait going.'
# the pointer moves and a button is pressed: a click, so never quiet
function Get-AgentPointerPosition { $s = 1000 + [int]($jt.ElapsedMilliseconds / 40); return [pscustomobject]@{ X = (500 + ($s % 2) * 30); Y = 400 } }
$script:buttonPressed = $true; $jt.Restart()
$r = Wait-AgentUserQuiet -QuietMilliseconds 300 -MaxWaitMilliseconds 600 -PollMilliseconds 20 -NoCue
Assert-True (-not $r.Quiet) 'Moving the pointer while pressing a button is clicking and must keep the wait going.'
$script:buttonPressed = $false
# a keystroke in the middle of the movement restarts the wait (the pointer is still while the key is pressed)
$jt.Restart(); $keyAt = 150
function Get-AgentPointerPosition { $s = 1000 + [int]($jt.ElapsedMilliseconds / 40); [pscustomobject]@{ X = (500 + $(if ([Math]::Abs($jt.ElapsedMilliseconds - $keyAt) -lt 60) { 0 } else { ($s % 2) * 3 })); Y = 400 } }
$r = Wait-AgentUserQuiet -QuietMilliseconds 300 -MaxWaitMilliseconds 3000 -PollMilliseconds 10 -NoCue
Assert-True ($r.Quiet -and $r.WaitedMilliseconds -ge ($keyAt + 250)) "A keystroke among the pointer movement must restart the quiet period. Result: $($r | ConvertTo-Json -Compress)"
function Get-AgentInputStamp { return [uint32]$script:stamp }
function Get-AgentUserIdleMilliseconds { return $script:idle }
function Get-AgentPointerPosition { return $script:pointer }
$script:stamp = 100; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:idle = 10000
# --- input stamp / Restore-AgentUserFocus ---
$context = [pscustomobject]@{ Foreground = [IntPtr]20; Focused = [pscustomobject]@{ Name = 'prompt' }; CursorX = 700; CursorY = 300 }
$script:foreground = [IntPtr]10; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:stamp = 100; $script:calls.Clear(); $script:focusedIs = $true
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True ($r.Restored -and $r.Foreground -and $r.Focus -and $r.Pointer -and $r.Reason -eq 'Restored') 'A quiet session must hand the window, focus and pointer back.'
Assert-True (($script:calls -join ';') -eq 'foreground:20;pointer:700,300') 'Hand-back order must be foreground then pointer, and no focus call when focus is already right.'
# the person used the keyboard or mouse since our last input: change nothing
$script:foreground = [IntPtr]10; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:calls.Clear(); $script:stamp = 101
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True (-not $r.Restored -and $r.Reason -eq 'UserInput' -and $script:calls.Count -eq 0) 'User input since the last own action must prevent any restore.'
# the hand-back with a pointer mark: the pointer moving alone is not the person, a button press is
$script:stamp = 101; $script:foreground = [IntPtr]10; $script:inUse = $null; $script:buttonPressed = $false; $script:calls.Clear()
$script:pointer = [pscustomobject]@{ X = 540; Y = 400 }
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100 -OwnPoint ([pscustomobject]@{ X = 500; Y = 400 })
Assert-True ($r.Restored -and $r.Reason -eq 'Restored' -and $r.Pointer) 'The pointer moving since the last agent step must not stop the hand-back.'
$script:foreground = [IntPtr]10; $script:buttonPressed = $true; $script:calls.Clear(); $script:pointer = [pscustomobject]@{ X = 540; Y = 400 }
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100 -OwnPoint ([pscustomobject]@{ X = 500; Y = 400 })
Assert-True (-not $r.Restored -and $r.Reason -eq 'UserInput' -and $script:calls.Count -eq 0) 'A button press since the last agent step must stop the hand-back.'
$script:buttonPressed = $false; $script:stamp = 100; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:foreground = [IntPtr]10# the person typed while the agent still held the target window: their window comes back, the pointer is left alone
$script:stamp = 101; $script:inUse = $null; $script:foreground = [IntPtr]10; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100 -HeldHandle ([IntPtr]10)
Assert-True ($r.Restored -and $r.Reason -eq 'RestoredAfterUserInput' -and $r.Foreground -and -not $r.Pointer -and ($script:calls -join ';') -eq 'foreground:20' -and $script:pointer.X -eq 500) 'Typing into the held window must give the person''s window back without touching the pointer.'
# the person typed and has already moved to another window themselves: nothing is changed
$script:foreground = [IntPtr]30; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100 -HeldHandle ([IntPtr]10)
Assert-True (-not $r.Restored -and $r.Reason -eq 'UserInput' -and $script:calls.Count -eq 0) 'A person who has moved to another window must not be pulled back.'
$script:stamp = 100; $script:foreground = [IntPtr]10
# a mouse button held since before the block (no new event): no window switch, no pointer move
$script:stamp = 100; $script:inUse = 'MouseButton'; $script:foreground = [IntPtr]10; $script:pointer = [pscustomobject]@{ X = 500; Y = 400 }; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True (-not $r.Restored -and $r.Reason -eq 'MouseButtonInUse' -and $script:calls.Count -eq 0 -and $script:pointer.X -eq 500) 'A held mouse button must prevent any window switch or pointer move.'
$script:inUse = 'Modifier'; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True (-not $r.Restored -and $r.Reason -eq 'ModifierInUse' -and $script:calls.Count -eq 0) 'A held modifier must prevent the hand-back.'
$script:inUse = $null
# saved window closed
$script:stamp = 100; $script:windows = @(10); $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True (-not $r.Restored -and $r.Reason -eq 'WindowGone' -and $script:calls.Count -eq 0) 'A closed saved window must not be restored.'
$script:windows = @(10, 20)
# already in front: no window switch
$script:foreground = [IntPtr]20; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True ($r.Restored -and -not ($script:calls -contains 'foreground:20')) 'A window that is already in front must not be re-activated.'
# nothing saved
Assert-True ((Restore-AgentUserFocus -Context ([pscustomobject]@{ Foreground = [IntPtr]::Zero; Focused = $null; CursorX = 0; CursorY = 0 }) -OwnStamp 1).Reason -eq 'NothingSaved') 'An empty context must say nothing was saved.'
# focus not restorable: reported, not claimed
$script:foreground = [IntPtr]10; $script:focusedIs = $false; $script:calls.Clear()
$r = Restore-AgentUserFocus -Context $context -OwnStamp 100
Assert-True (-not $r.Restored -and $r.Reason -eq 'NotVerified' -and -not $r.Focus) 'An unverified focus must be reported as not restored.'
# no saved control (an app that exposes none): the window and pointer still go back
$script:focusedIs = $true; $script:foreground = [IntPtr]10
$r = Restore-AgentUserFocus -Context ([pscustomobject]@{ Foreground = [IntPtr]20; Focused = $null; CursorX = 700; CursorY = 300 }) -OwnStamp 100
Assert-True ($r.Restored -and $r.Focus) 'Without a saved control the window and pointer must still be restored.'

Write-Output "PASS: $script:assertions assertions; quiet wait (idle, active, draft buffer, unknown idle, resume), input stamp and focus handback (order, user input wins, closed window, unverified focus); all native calls mocked, no keyboard, mouse or focus touched."
