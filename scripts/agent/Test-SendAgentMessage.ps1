<#
.SYNOPSIS
Offline checks of the tiered message router (mailbox, UI sender, conservative UI sender); no chat, UI or mailbox files.
.DESCRIPTION
Extracts the router's functions through its AST and mocks the mailbox and the UI sender. Nothing is sent anywhere.
#>
[CmdletBinding()]
param([string]$RouterPath)
$ErrorActionPreference = 'Stop'
if (-not $RouterPath) { $RouterPath = Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Send-AgentMessage.ps1' }
Set-StrictMode -Version 2
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $RouterPath).Path, [ref]$null, [ref]$null)
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
foreach ($name in @('Test-MechanicalUiFailure', 'New-BootstrapText', 'Invoke-AgentMessage')) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Missing function: $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Reset-Scenario {
    $script:Hwnd = '0x240CCA'; $script:TitleContains = $null; $script:Text = 'hello'; $script:Mode = 'Auto'
    $script:Bootstrap = $false; $script:StopListening = $false; $script:AckTimeoutSeconds = 5
    $script:NewSession = $false; $script:Steer = $false; $script:OverwriteInput = $false; $script:AllowOwnHost = $false
    $script:IgnoreBanners = $false; $script:IgnoreUserActivity = $false; $script:SpeakRequest = $false
    $script:QuietSeconds = 3; $script:MaxWaitSeconds = 120; $script:ChannelName = 'w240cca'; $script:ReListenWaitSeconds = 8
    $script:state = [pscustomobject]@{ Registered = $false; Live = $false; Reason = 'NoListener'; ListenerPid = 0; BeatAgeMs = $null; LastExitReason = $null; LastExitAgeMs = $null }
    $script:post = [pscustomobject]@{ Delivered = $true; Id = 'abc123abc123'; AckMs = 250; Reason = 'Delivered' }
    $script:uiResults = New-Object 'System.Collections.Generic.Queue[object]'
    $script:calls = New-Object 'System.Collections.Generic.List[string]'
    $script:uiArgs = New-Object 'System.Collections.Generic.List[hashtable]'
    $script:postKinds = New-Object 'System.Collections.Generic.List[string]'
}
function Get-MailboxState { param($Channel) $script:calls.Add('state'); return $script:state }
function Send-AgentMailboxMessage { param($Channel, $Text, $Kind = 'message', $AckTimeoutMs) $script:calls.Add('post'); $script:postKinds.Add($Kind); return $script:post }
function Invoke-UiSender { param([hashtable]$Arguments) $script:calls.Add('ui'); $script:uiArgs.Add($Arguments.Clone()); return $script:uiResults.Dequeue() }
function New-Ui([bool]$Sent, [string]$Err = $null, [string]$InputValue = $null) { [pscustomobject]@{ Sent = $Sent; Attempts = 1; InputText = $InputValue; Error = $Err } }

# ---- which failures are worth the older steps ----
foreach ($mechanical in @('Not sent; input never matched the prompt. Last error: read-back-mismatch: x', 'Send click failed: element-not-found ', 'Could not bring the target window to the foreground, even after a second try.', 'verify-unstable: changed')) {
    Assert-True (Test-MechanicalUiFailure -ErrorText $mechanical) "Mechanical failure not recognised: $mechanical"
}
foreach ($decision in @($null, '', 'InputNotEmpty: the chat input holds a draft.', 'UserActive: the keyboard stayed in use', 'DoNotDisturb (PresentationMode): x', 'InputOffScreen: the chat input centre', 'Chat shows HarnessWorkspaceMismatchBanner: x', 'OwnHostWindow: window 0x1 belongs to process 4', 'UiBusy: other agents kept the keyboard', 'SessionNotPresent: locked', 'Window 0x1 is on another virtual desktop', 'SteerRequiresBusy: no', 'SenderFailed: boom')) {
    Assert-True (-not (Test-MechanicalUiFailure -ErrorText $decision)) "A refusal or decision must not be retried with the older steps: $decision"
}

# ---- tier 1: a live listener takes the message ----
Reset-Scenario; $state = $script:state; $script:state = [pscustomobject]@{ Registered = $true; Live = $true; Reason = 'Listening'; ListenerPid = 4; BeatAgeMs = 100; LastExitReason = $null; LastExitAgeMs = $null }
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Mailbox' -and $r.MessageId -eq 'abc123abc123' -and $script:calls -notcontains 'ui') 'A delivered mailbox message must be the whole send: no UI call.'

# ---- mailbox did not take it: UI tier, steer because the chat was listening ----
Reset-Scenario; $script:state = [pscustomobject]@{ Registered = $true; Live = $true; Reason = 'Listening'; ListenerPid = 4; BeatAgeMs = 100; LastExitReason = $null; LastExitAgeMs = $null }
$script:post = [pscustomobject]@{ Delivered = $false; Id = 'x'; AckMs = $null; Reason = 'NotClaimed: withdrawn' }
$script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and $script:uiArgs.Count -eq 1 -and $script:uiArgs[0].Steer -eq $true -and -not $script:uiArgs[0].ContainsKey('Conservative')) 'After an unclaimed mailbox message the UI sender must run with -Steer (a listening chat is busy).'
Assert-True (($r.Attempts -join '|') -match 'Mailbox: NotClaimed' -and ($r.Attempts -join '|') -match 'Ui: sent') 'The result must list each tier tried.'

# ---- stale registration, chat idle again: steer refused, plain send follows ----
Reset-Scenario; $script:state = [pscustomobject]@{ Registered = $true; Live = $false; Reason = 'HeartbeatStale'; ListenerPid = 4; BeatAgeMs = 9000; LastExitReason = $null; LastExitAgeMs = $null }
$script:uiResults.Enqueue((New-Ui $false 'SteerRequiresBusy: the visible input area does not confirm a busy chat; nothing was typed or clicked.'))
$script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and $script:uiArgs.Count -eq 2 -and $script:uiArgs[0].Steer -eq $true -and -not $script:uiArgs[1].ContainsKey('Steer')) 'A stale listener whose chat is idle again must fall back to a plain send after the steer is refused.'
Assert-True ($script:calls -notcontains 'post') 'A stale listener must never be posted to.'

# ---- never listened: plain UI send ----
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and -not $script:uiArgs[0].ContainsKey('Steer') -and $script:uiArgs[0].Quiet -eq $true -and $script:uiArgs[0].Hwnd -eq '0x240CCA') 'With no mailbox history the first tier is a plain, quiet UI send to the window.'

# ---- tier 3: only for mechanical failures ----
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $false 'Not sent; input never matched the prompt. Last error: read-back-mismatch: x' 'garbled')); $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Conservative' -and $script:uiArgs.Count -eq 2 -and $script:uiArgs[1].Conservative -eq $true -and -not $script:uiArgs[1].ContainsKey('OverwriteInput')) 'A mechanical failure must retry once with -Conservative, without overwriting text that is not ours.'
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $false 'Send click failed: element-not-found ' 'go')); $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Conservative' -and $script:uiArgs[1].OverwriteInput -eq $true) 'After a failed Send click that left exactly our own prompt, the second try may replace it.'
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $false 'InputNotEmpty: the chat input holds a draft. DraftLength=3'))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $r.Sent -and $r.Tier -eq 'None' -and $script:uiArgs.Count -eq 1 -and $r.Error -match '^InputNotEmpty') 'A draft refusal must be returned as it is; the older steps would meet the same draft.'
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $false 'UserActive: the keyboard or mouse stayed in use for 120 s.'))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $r.Sent -and $script:uiArgs.Count -eq 1) 'A person at the keyboard must not trigger a second UI attempt.'
Reset-Scenario; $script:uiResults.Enqueue((New-Ui $false 'Send click failed: x')); $script:uiResults.Enqueue((New-Ui $false 'Not sent; input never matched the prompt.'))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $r.Sent -and $r.Tier -eq 'None' -and $script:uiArgs.Count -eq 2 -and $r.Error -match 'never matched' -and @($r.Attempts).Count -eq 3 -and (@($r.Attempts)[0] -match '^Mailbox: not used')) 'When both UI tiers fail the result must say so with each reason and stop.'

# ---- modes and switches ----
Reset-Scenario; $script:Mode = 'Mailbox'
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $r.Sent -and $script:uiArgs.Count -eq 0 -and $r.Error -match '^Mailbox mode: not delivered') 'Mailbox mode must never fall back to the UI.'
Reset-Scenario; $script:Mode = 'Ui'; $script:uiResults.Enqueue((New-Ui $false 'Send click failed: x'))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $r.Sent -and $script:calls -notcontains 'state' -and $script:calls -notcontains 'post' -and $script:uiArgs.Count -eq 1) 'Ui mode must not consult the mailbox and must not try the conservative tier.'
Reset-Scenario; $script:Mode = 'Conservative'; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Conservative' -and $script:uiArgs.Count -eq 1 -and $script:uiArgs[0].Conservative -eq $true -and $script:calls -notcontains 'post') 'Conservative mode must go straight to the conservative sender.'
Reset-Scenario; $script:NewSession = $true; $script:state = [pscustomobject]@{ Registered = $true; Live = $true; Reason = 'Listening'; ListenerPid = 4; BeatAgeMs = 1; LastExitReason = $null; LastExitAgeMs = $null }; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and $script:calls -notcontains 'post' -and $script:uiArgs[0].NewSession -eq $true -and -not $script:uiArgs[0].ContainsKey('Steer')) 'A new session can only be made through the UI, and is never a steer.'
Reset-Scenario; $script:Bootstrap = $true; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $script:calls -notcontains 'post') 'Bootstrap goes through the UI tiers: an idle chat cannot be woken by a mailbox.'
Reset-Scenario; $script:Steer = $true; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($script:uiArgs[0].Steer -eq $true) 'An explicit -Steer must reach the UI sender.'
Reset-Scenario; $script:AllowOwnHost = $true; $script:IgnoreUserActivity = $true; $script:Hwnd = $null; $script:TitleContains = 'My window'; $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($script:uiArgs[0].AllowOwnHost -eq $true -and $script:uiArgs[0].IgnoreUserActivity -eq $true -and $script:uiArgs[0].TitleContains -eq 'My window' -and -not $script:uiArgs[0].ContainsKey('Hwnd') -and -not $script:uiArgs[0].ContainsKey('IgnoreBanners')) 'Pass-through switches and the title lookup must reach the UI sender, and only those that were given.'

# ---- stop ----
Reset-Scenario; $script:StopListening = $true; $script:state = [pscustomobject]@{ Registered = $true; Live = $true; Reason = 'Listening'; ListenerPid = 4; BeatAgeMs = 1; LastExitReason = $null; LastExitAgeMs = $null }
$r = Invoke-AgentMessage -MessageText $null
Assert-True ($r.Sent -and $r.Tier -eq 'Mailbox' -and $script:postKinds[0] -eq 'stop') 'StopListening must post a stop message.'
Reset-Scenario; $script:StopListening = $true
$r = Invoke-AgentMessage -MessageText $null
Assert-True (-not $r.Sent -and $script:uiArgs.Count -eq 0 -and $r.Error -match '^StopListening') 'StopListening with no live listener must send nothing, not type "stop" into a chat.'

# ---- a worker that just took a message listens again within seconds: wait for it instead of typing ----
function New-StateObject([bool]$Live, [string]$ExitReason, $ExitAgeMs) { [pscustomobject]@{ Registered = $Live; Live = $Live; Reason = $(if ($Live) { 'Listening' } else { 'NoListener' }); ListenerPid = 4; BeatAgeMs = 1; LastExitReason = $ExitReason; LastExitAgeMs = $ExitAgeMs } }
Reset-Scenario; $script:stateQueue = New-Object 'System.Collections.Generic.Queue[object]'
foreach ($s in @((New-StateObject $false 'message' 3000), (New-StateObject $false 'message' 3200), (New-StateObject $true $null $null))) { $script:stateQueue.Enqueue($s) }
function Get-MailboxState { param($Channel) $script:calls.Add('state'); if ($script:stateQueue.Count -gt 1) { return $script:stateQueue.Dequeue() } else { return $script:stateQueue.Peek() } }
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Mailbox' -and ($r.Attempts -join '|') -eq '' -or ($r.Sent -and $r.Tier -eq 'Mailbox' -and $script:uiArgs.Count -eq 0)) 'A worker that has just taken a message must be waited for, then given the message by mailbox, with no UI send.'
Reset-Scenario; $script:stateQueue = New-Object 'System.Collections.Generic.Queue[object]'; $script:stateQueue.Enqueue((New-StateObject $false 'message' 3000)); $script:ReListenWaitSeconds = 1
$script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and $script:uiArgs[0].Steer -eq $true -and ($r.Attempts -join '|') -match 'it did not') 'A worker that does not listen again in time is steered by the UI (it is busy), not sent a plain message.'
foreach ($case in @(@{ Reason = 'stop'; Age = 3000; Label = 'told to stop' }, @{ Reason = 'message'; Age = 60000; Label = 'last listened a minute ago' }, @{ Reason = $null; Age = $null; Label = 'never listened' })) {
    Reset-Scenario; $script:stateQueue = New-Object 'System.Collections.Generic.Queue[object]'; $script:stateQueue.Enqueue((New-StateObject $false $case.Reason $case.Age)); $script:uiResults.Enqueue((New-Ui $true))
    $r = Invoke-AgentMessage -MessageText 'go'
    Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and ($r.Attempts -join '|') -notmatch 'waited') "A worker $($case.Label) must not be waited for."
}
Reset-Scenario; $script:stateQueue = New-Object 'System.Collections.Generic.Queue[object]'; $script:stateQueue.Enqueue((New-StateObject $false 'stop' 3000)); $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True (-not $script:uiArgs[0].ContainsKey('Steer')) 'A worker that was told to stop is idle: a plain send, not a steer.'
Reset-Scenario; $script:ReListenWaitSeconds = 0; $script:stateQueue = New-Object 'System.Collections.Generic.Queue[object]'; $script:stateQueue.Enqueue((New-StateObject $false 'timeout' 2000)); $script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and ($r.Attempts -join '|') -notmatch 'waited' -and $script:uiArgs[0].Steer -eq $true) 'With the wait turned off the UI sender runs at once, steering a chat that was listening.'
# ---- an exception in the mailbox layer is a tier failure, not the end ----
Reset-Scenario
function Get-MailboxState { param($Channel) throw 'disk error' }
$script:uiResults.Enqueue((New-Ui $true))
$r = Invoke-AgentMessage -MessageText 'go'
Assert-True ($r.Sent -and $r.Tier -eq 'Ui' -and ($r.Attempts -join '|') -match 'Mailbox: error \(disk error\)') 'A failing mailbox layer must fall back to the UI sender.'

# ---- bootstrap text ----
$script:ScriptDir = 'C:\skills\agent-orchestrator\scripts'
$text = New-BootstrapText -Task 'Fix the build.' -ChannelName 'w240cca'
Assert-True ($text -match '^Fix the build\. Mailbox mode:' -and $text -match 'scripts\\Wait-AgentMailbox\.ps1" -Channel w240cca' -and $text -match 'MAILBOX TIMEOUT' -and $text -match 'MAILBOX STOP' -and $text -match 'two MAILBOX TIMEOUTs in a row' -and $text -match 'From orchestrator:' -and $text -notmatch "[`r`n]") 'The bootstrap must be one line carrying the task, the exact command and the timeout and stop rules.'
$src = $ast.Extent.Text
Assert-True ($src -match 'NotePropertyName Preview' -and $src -match 'NotePropertyName Display' -and $src -match 'Master -> worker') 'The result must carry a Preview and a one-line Display for the person.'
Assert-True ($src -match "'Auto', 'Mailbox', 'Ui', 'Conservative'" -and $src -match '\[ValidateRange\(1, 60\)\]\s+\[int\]\$AckTimeoutSeconds') 'The mode names and the ack limit must be as documented.'
"PASS: $script:assertions assertions; tier order (mailbox, UI, conservative), refusals not retried, steer for a listening chat, stale listener, modes, pass-through switches, stop, mailbox-layer failure and bootstrap text; sender and mailbox mocked."
